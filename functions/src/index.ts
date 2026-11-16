// functions/src/index.ts
// 他人のデータを書き換える操作と、課金プランで制限する読み取りはすべてここで行う。
import { randomBytes } from "crypto";
import { initializeApp } from "firebase-admin/app";
import {
  DocumentSnapshot,
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();

setGlobalOptions({ region: "asia-northeast1", maxInstances: 100 });

// 💡 App Check を必須にし、改造クライアントやスクリプトからの直接呼び出しを防ぐ
const OPTS = { enforceAppCheck: true };

const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const PAGE_SIZE = 20;
const REQUIRED_MESSAGES = 4; // 友達申請に必要な「お互いの送信数」
const FOOTPRINT_THROTTLE_MS = 10 * 60 * 1000; // 同じ相手への足跡は10分に1回まで更新

// プランごとに「モザイクにする」対象
const LOCKED_PLANS: Record<"likedBy" | "footprints", string[]> = {
  likedBy: ["free", "light"],
  footprints: ["free"],
};

// ---------------------------------------------------------------------------
// ヘルパー
// ---------------------------------------------------------------------------
function authUid(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "ログインが必要です");
  return uid;
}

function peerIdOf(req: CallableRequest, self: string): string {
  const v = (req.data as Record<string, unknown> | null)?.peerId;
  if (typeof v !== "string" || !UID_RE.test(v)) {
    throw new HttpsError("invalid-argument", "不正なユーザーIDです");
  }
  if (v === self) {
    throw new HttpsError("invalid-argument", "自分自身は指定できません");
  }
  return v;
}

const userRef = (uid: string) => db.collection("users").doc(uid);
const sub = (uid: string, name: string, peerId: string) =>
  userRef(uid).collection(name).doc(peerId);
const requestRef = (fromId: string, toId: string) =>
  db.collection("friend_requests").doc(`${fromId}_${toId}`);
// チャットルームIDは「小さいuid_大きいuid」（アプリ側の ([a, b]..sort()).join("_") と同じ）
const roomRef = (a: string, b: string) =>
  db.collection("chat_rooms").doc([a, b].sort().join("_"));

function summary(snap: DocumentSnapshot) {
  const d = snap.data() ?? {};
  const images = Array.isArray(d.imageUrls) ? d.imageUrls : [];
  return {
    name: typeof d.name === "string" ? d.name : "ユーザー",
    thumbnailUrl:
      typeof d.thumbnailUrl === "string"
        ? d.thumbnailUrl
        : typeof images[0] === "string"
          ? images[0]
          : "",
    gender: typeof d.gender === "string" ? d.gender : null,
  };
}

// ---------------------------------------------------------------------------
// 招待コードの発行（ユーザーごとに1つ、重複なし）
// 見間違えやすい文字（0/O, 1/I）を除いた32文字 × 8桁 ≒ 1兆通り
// （32文字ちょうどにすることで、乱数の偏りが出ないようにしている）
// ---------------------------------------------------------------------------
const INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const INVITE_LENGTH = 8;

function randomInviteCode(): string {
  const bytes = randomBytes(INVITE_LENGTH);
  let code = "";
  for (const b of bytes) code += INVITE_ALPHABET[b % INVITE_ALPHABET.length];
  return code;
}

export const getInviteCode = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const ownerRef = db.collection("invite_owners").doc(uid);

  const existing = await ownerRef.get();
  const existingCode = existing.get("code");
  if (typeof existingCode === "string") return { code: existingCode };

  // ほぼ起きないが、他人と同じコードになった場合は作り直す
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomInviteCode();
    const codeRef = db.collection("invite_codes").doc(code);

    const issued = await db.runTransaction(async (tx) => {
      const [owner, codeSnap] = await tx.getAll(ownerRef, codeRef);
      const already = owner.get("code");
      if (typeof already === "string") return already; // 同時実行で先に発行済み
      if (codeSnap.exists) return null;

      const now = FieldValue.serverTimestamp();
      tx.create(codeRef, { uid, createdAt: now });
      tx.set(ownerRef, { code, createdAt: now });
      return code;
    });

    if (issued) return { code: issued };
  }
  throw new HttpsError("unavailable", "招待コードを発行できませんでした。もう一度お試しください");
});

// ---------------------------------------------------------------------------
// 友達申請の送信（条件はすべてサーバーで確認する）
// ---------------------------------------------------------------------------
export const sendFriendRequest = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);

  const [me, peer, myBlock, peerBlock, friend, room, incoming] = await db.getAll(
    userRef(uid),
    userRef(peerId),
    sub(uid, "blocks", peerId),
    sub(peerId, "blocks", uid),
    sub(uid, "friends", peerId),
    roomRef(uid, peerId),
    requestRef(peerId, uid),
  );

  if (!peer.exists || myBlock.exists || peerBlock.exists) {
    throw new HttpsError("failed-precondition", "このユーザーには申請できません");
  }
  if (friend.exists) {
    throw new HttpsError("failed-precondition", "既に友達です");
  }

  const name = me.get("name");
  if (typeof name !== "string" || !name.trim() || name.trim() === "名前未設定") {
    throw new HttpsError("failed-precondition", "先にプロフィールで名前を設定してください");
  }

  // 💡 「お互い4通以上」の条件は改造アプリでも回避できないようサーバーで判定する
  const counts = (room.get("messageCountBy") ?? {}) as Record<string, unknown>;
  const myCount = typeof counts[uid] === "number" ? (counts[uid] as number) : 0;
  const peerCount = typeof counts[peerId] === "number" ? (counts[peerId] as number) : 0;
  if (myCount < REQUIRED_MESSAGES || peerCount < REQUIRED_MESSAGES) {
    throw new HttpsError(
      "failed-precondition",
      `お互いに${REQUIRED_MESSAGES}通以上やり取りすると申請できます`,
    );
  }

  if (incoming.exists) {
    throw new HttpsError(
      "failed-precondition",
      "相手から申請が届いています。友達タブから承認してください",
    );
  }

  try {
    // create() は既に存在すると失敗する → 重複申請を確実に防げる
    await requestRef(uid, peerId).create({
      fromId: uid,
      toId: peerId,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if ((e as { code?: number }).code === 6) {
      throw new HttpsError("already-exists", "既に申請済みです");
    }
    throw e;
  }
  return { ok: true };
});

// ---------------------------------------------------------------------------
// メッセージ送信数のカウント（友達申請の条件判定に使う）
// アプリ側でメッセージを数えるために全件を読み込むのをやめ、ここで1件ずつ加算する。
// ※ トリガーはまれに2回実行されることがあるため、厳密な件数ではなく「4通以上か」の判定用
// ---------------------------------------------------------------------------
export const onMessageCreated = onDocumentCreated(
  "chat_rooms/{roomId}/messages/{messageId}",
  async (event) => {
    const senderId = event.data?.get("senderId");
    if (typeof senderId !== "string" || !UID_RE.test(senderId)) return;

    await db
      .collection("chat_rooms")
      .doc(event.params.roomId)
      .set(
        { messageCountBy: { [senderId]: FieldValue.increment(1) } },
        { merge: true },
      );
  },
);

// ---------------------------------------------------------------------------
// 友達申請の承認
// ---------------------------------------------------------------------------
export const acceptFriendRequest = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const requestId = (req.data as Record<string, unknown> | null)?.requestId;
  if (
    typeof requestId !== "string" ||
    requestId.length > 300 ||
    requestId.includes("/")
  ) {
    throw new HttpsError("invalid-argument", "不正な申請IDです");
  }

  const result = await db.runTransaction(async (tx) => {
    const reqDoc = db.collection("friend_requests").doc(requestId);
    const reqSnap = await tx.get(reqDoc);
    if (!reqSnap.exists) return "gone" as const;

    const r = reqSnap.data()!;
    // 💡 自分宛ての申請以外は承認できない（他人の申請を勝手に承認する攻撃を防ぐ）
    if (r.toId !== uid) {
      throw new HttpsError("permission-denied", "この申請は操作できません");
    }
    if (r.status !== "pending" || typeof r.fromId !== "string") {
      return "gone" as const;
    }
    const fromId: string = r.fromId;

    const [me, peer, myBlock, peerBlock] = await tx.getAll(
      userRef(uid),
      userRef(fromId),
      sub(uid, "blocks", fromId),
      sub(fromId, "blocks", uid),
    );

    if (!peer.exists || myBlock.exists || peerBlock.exists) {
      tx.delete(reqDoc);
      return "unavailable" as const;
    }

    const now = FieldValue.serverTimestamp();
    tx.set(sub(uid, "friends", fromId), { ...summary(peer), createdAt: now });
    tx.set(sub(fromId, "friends", uid), { ...summary(me), createdAt: now });
    tx.delete(reqDoc);
    tx.delete(requestRef(uid, fromId)); // 逆方向の申請も残さない
    return "ok" as const;
  });

  if (result === "gone") {
    throw new HttpsError("failed-precondition", "この申請は既に処理されています");
  }
  if (result === "unavailable") {
    throw new HttpsError("failed-precondition", "このユーザーとは友達になれません");
  }
  return { ok: true };
});

// ---------------------------------------------------------------------------
// 友達解除
// ---------------------------------------------------------------------------
export const removeFriend = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);

  const batch = db.batch();
  batch.delete(sub(uid, "friends", peerId));
  batch.delete(sub(peerId, "friends", uid));
  await batch.commit();
  return { ok: true };
});

// ---------------------------------------------------------------------------
// ブロック（関係データを双方向で掃除する）
// ---------------------------------------------------------------------------
export const blockUser = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);

  const [peer, room] = await db.getAll(userRef(peerId), roomRef(uid, peerId));
  if (!peer.exists) throw new HttpsError("not-found", "ユーザーが見つかりません");

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(sub(uid, "blocks", peerId), { createdAt: now });
  batch.set(sub(peerId, "blockedBy", uid), { createdAt: now });

  // 💡 チャットルームに印を付け、お互いのトーク一覧から消す
  if (room.exists) {
    batch.update(room.ref, { blockedBy: FieldValue.arrayUnion(uid) });
  }

  for (const [a, b] of [
    [uid, peerId],
    [peerId, uid],
  ]) {
    for (const col of ["friends", "likes", "likedBy", "footprints"]) {
      batch.delete(sub(a, col, b));
    }
    batch.delete(requestRef(a, b));
  }
  await batch.commit();
  return { ok: true };
});

// ---------------------------------------------------------------------------
// いいね（他画面から呼ぶ。相手側の likedBy はサーバーだけが書ける）
// ---------------------------------------------------------------------------
export const likeUser = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);

  const [peer, b1, b2] = await db.getAll(
    userRef(peerId),
    sub(uid, "blocks", peerId),
    sub(peerId, "blocks", uid),
  );
  if (!peer.exists || b1.exists || b2.exists) {
    throw new HttpsError("failed-precondition", "このユーザーにはいいねできません");
  }
  // TODO: プランごとの1日あたりのいいね上限をここで判定する

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(sub(uid, "likes", peerId), { createdAt: now });
  batch.set(sub(peerId, "likedBy", uid), { createdAt: now });
  await batch.commit();
  return { ok: true };
});

// ---------------------------------------------------------------------------
// 足跡（ProfileDetailScreen 表示時に呼ぶ）
// ---------------------------------------------------------------------------
export const recordFootprint = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);

  const [peer, b1, b2, existing] = await db.getAll(
    userRef(peerId),
    sub(uid, "blocks", peerId),
    sub(peerId, "blocks", uid),
    sub(peerId, "footprints", uid),
  );
  if (!peer.exists || b1.exists || b2.exists) return { ok: true }; // 理由は伝えない

  const last = existing.get("createdAt") as Timestamp | undefined;
  if (last && Date.now() - last.toMillis() < FOOTPRINT_THROTTLE_MS) {
    return { ok: true };
  }
  await sub(peerId, "footprints", uid).set({
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// いいねされた／足跡の取得（プラン判定はサーバーで行い、
// ロック中は相手のIDも名前も画像も返さない）
// ---------------------------------------------------------------------------
export const getInbox = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const data = (req.data ?? {}) as Record<string, unknown>;
  const type = data.type;
  if (type !== "likedBy" && type !== "footprints") {
    throw new HttpsError("invalid-argument", "不正な種別です");
  }

  // 💡 plan はルールでクライアントから書き換え不可にしている前提
  const me = await userRef(uid).get();
  const rawPlan = me.get("plan");
  const plan = typeof rawPlan === "string" ? rawPlan : "free";
  const locked = LOCKED_PLANS[type].includes(plan);

  const col = userRef(uid).collection(type);
  let q = col.orderBy("createdAt", "desc").limit(PAGE_SIZE);

  const cursor = data.cursor;
  if (cursor !== undefined && cursor !== null) {
    if (typeof cursor !== "string" || !/^\d{1,12}\.\d{1,9}$/.test(cursor)) {
      throw new HttpsError("invalid-argument", "不正なカーソルです");
    }
    const [s, n] = cursor.split(".").map(Number);
    q = q.startAfter(new Timestamp(s, n));
  }

  const [page, countSnap] = await Promise.all([
    q.get(),
    cursor ? Promise.resolve(null) : col.count().get(),
  ]);

  const total = countSnap ? countSnap.data().count : null;
  const lastDoc = page.docs[page.docs.length - 1];
  const lastTs = lastDoc?.get("createdAt") as Timestamp | undefined;
  const nextCursor =
    page.size === PAGE_SIZE && lastTs
      ? `${lastTs.seconds}.${lastTs.nanoseconds}`
      : null;

  if (locked) {
    return { locked: true, total, items: page.docs.map(() => ({})), nextCursor };
  }

  const profiles = page.empty
    ? []
    : await db.getAll(...page.docs.map((d) => userRef(d.id)));
  const items = profiles
    .filter((p) => p.exists)
    .map((p) => ({ id: p.id, ...summary(p) }));

  return { locked: false, total, items, nextCursor };
});