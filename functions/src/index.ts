// functions/src/index.ts
// 他人のデータを書き換える操作と、課金プランで制限する読み取りはすべてここで行う。
import { randomBytes } from "crypto";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import {
  DocumentSnapshot,
  FieldPath,
  FieldValue,
  getFirestore,
  QueryDocumentSnapshot,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

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
// 💡 料金プラン（2026年11月改定）
//   free     … 0円   ：トーク開始 月5人。足跡・いいねはモザイク
//   light    … 250円 ：トーク開始 月15人。足跡・いいねした人を見られる
//   standard … 480円 ：トーク開始 月40人。足跡・いいねした人を見られる
//   premium  … 980円 ：トーク開始 無制限。足跡・いいね ＋ 検索でプロフィール優先表示
const LOCKED_PLANS: Record<"likedBy" | "footprints", string[]> = {
  likedBy: ["free"],
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
// メッセージが送られたときの処理（トークルームの情報をサーバーで更新する）
//
// ・lastMessage / lastMessageTime … トーク一覧に表示する最新メッセージ
// ・unreadCount.{相手}            … 相手の未読数を +1
// ・messageCountBy.{送信者}       … 友達申請の条件（お互い4通以上）の判定用
//
// 💡 以前はアプリがこれらを書き込んでいたため、改造アプリで
//    「相手の未読数を999にする」「送信数を水増しする」などができた。
//    サーバーで書き込むことで、改ざんできなくなる。
// ※ トリガーはまれに2回実行されることがあるため、件数は厳密ではない（判定用には十分）
// ---------------------------------------------------------------------------
const LAST_MESSAGE_PREVIEW_LENGTH = 100;

// ---------------------------------------------------------------------------
// 限定バッジ：メッセージを送った「人数」に応じてプレゼント
//   5人 → 銀バッジ（silver）／10人 → 金バッジ（gold）
// 💡 人数・バッジはサーバーだけが書き込む（ルールでアプリからの書き換えを禁止）。
//    users/{uid}/messaged_peers/{相手} に「送ったことがある印」を1件だけ作り、
//    印が新しくできたときだけ人数を +1 する（トリガーが2回動いても二重に数えない）
// ---------------------------------------------------------------------------
const BADGE_RULES: { badge: "silver" | "gold"; peers: number }[] = [
  { badge: "gold", peers: 10 },
  { badge: "silver", peers: 5 },
];
const BADGE_RANK: Record<string, number> = { silver: 1, gold: 2 };

function badgeFor(count: number): "silver" | "gold" | null {
  for (const rule of BADGE_RULES) if (count >= rule.peers) return rule.badge;
  return null;
}

export const onMessageCreated = onDocumentCreated(
  "chat_rooms/{roomId}/messages/{messageId}",
  async (event) => {
    const msg = event.data;
    if (!msg) return;

    const senderId = msg.get("senderId");
    if (typeof senderId !== "string" || !UID_RE.test(senderId)) return;

    const members = event.params.roomId.split("_");
    if (members.length !== 2 || !members.includes(senderId)) return;
    const peerId = members[0] === senderId ? members[1] : members[0];

    const rawText = msg.get("text");
    const preview =
      typeof rawText === "string" ? rawText.slice(0, LAST_MESSAGE_PREVIEW_LENGTH) : "";
    const createdAt = msg.get("createdAt");
    const sentAt = createdAt instanceof Timestamp ? createdAt : Timestamp.now();

    const roomDoc = db.collection("chat_rooms").doc(event.params.roomId);

    const senderDoc = userRef(senderId);
    const markerDoc = sub(senderId, "messaged_peers", peerId);

    await db.runTransaction(async (tx) => {
      // 💡 トランザクションでは「読む」をすべて先に行う
      const [room, marker, sender] = await Promise.all([
        tx.get(roomDoc),
        tx.get(markerDoc),
        tx.get(senderDoc),
      ]);
      if (!room.exists) return; // 退会などでルームが消えている

      // --- 限定バッジ：この相手に初めてメッセージを送ったときだけ人数を数える ---
      if (!marker.exists && sender.exists) {
        const prev = sender.get("messagedPeersCount");
        const count = (typeof prev === "number" ? prev : 0) + 1;
        const userUpdate: Record<string, unknown> = { messagedPeersCount: count };

        const newBadge = badgeFor(count);
        const currentBadge = sender.get("badge");
        const currentRank = typeof currentBadge === "string" ? BADGE_RANK[currentBadge] ?? 0 : 0;
        if (newBadge && BADGE_RANK[newBadge] > currentRank) {
          userUpdate.badge = newBadge;
          userUpdate.badgeAwardedAt = FieldValue.serverTimestamp();
        }

        // peerId は、相手が退会したときに印を探して消すために入れておく
        tx.set(markerDoc, { peerId, createdAt: FieldValue.serverTimestamp() });
        tx.set(senderDoc, userUpdate, { merge: true });
      }

      const update: Record<string, unknown> = {
        messageCountBy: { [senderId]: FieldValue.increment(1) },
        unreadCount: { [peerId]: FieldValue.increment(1) },
      };

      // 💡 トリガーの実行順が前後しても、古いメッセージで上書きしない
      const current = room.get("lastMessageTime");
      if (!(current instanceof Timestamp) || current.toMillis() <= sentAt.toMillis()) {
        update.lastMessage = preview;
        update.lastMessageTime = sentAt;
        update.lastSenderId = senderId;
      }

      tx.set(roomDoc, update, { merge: true });
    });
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
    // 💡 退会時に「自分が他人に付けた足跡」を探して消せるよう、訪問者IDも保存する
    visitorId: uid,
  });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// いいねの取り消し
// ---------------------------------------------------------------------------
export const unlikeUser = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);

  const batch = db.batch();
  batch.delete(sub(uid, "likes", peerId));
  batch.delete(sub(peerId, "likedBy", uid));
  await batch.commit();
  return { ok: true };
});

// ---------------------------------------------------------------------------
// ブロックの解除
// ---------------------------------------------------------------------------
export const unblockUser = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);

  const [room, peer] = await db.getAll(roomRef(uid, peerId), userRef(peerId));
  const batch = db.batch();
  batch.delete(sub(uid, "blocks", peerId));
  batch.delete(sub(peerId, "blockedBy", uid));
  // 自分が付けたブロックの印だけ外す（相手からのブロックは残る）
  if (room.exists) {
    batch.update(room.ref, { blockedBy: FieldValue.arrayRemove(uid) });
  }
  // ⚠️ 移行用：古い方式（users ドキュメントの配列）のブロックも外す
  batch.set(userRef(uid), { blocks: FieldValue.arrayRemove(peerId) }, { merge: true });
  if (peer.exists) {
    batch.update(peer.ref, { blockedBy: FieldValue.arrayRemove(uid) });
  }
  await batch.commit();
  return { ok: true };
});

// ---------------------------------------------------------------------------
// 新規トーク開始の月間上限
// 💡 回数はクライアントから書き換えられない talk_quotas に保存する
//    （以前は自分の users ドキュメントにあり、自分で0に戻せば上限を無視できた）
// ---------------------------------------------------------------------------
// 💡 月に新しくトークを始められる人数（ここにないプラン＝premium は無制限）
const TALK_LIMITS: Record<string, number> = { free: 5, light: 15, standard: 40 };

function talkLimitOf(plan: unknown): number | null {
  const p = typeof plan === "string" ? plan : "free";
  return p in TALK_LIMITS ? TALK_LIMITS[p] : null;
}

// 💡 今の時点で有効なプラン。
//    無料体験（planSource = "trial"）の期限が過ぎていれば、体験前のプランとして扱う。
//    期限切れを元に戻すスケジュール関数は1時間ごとなので、その間もずれないようにする
function effectivePlan(user: DocumentSnapshot): string {
  const raw = user.get("plan");
  const plan = typeof raw === "string" ? raw : "free";
  if (user.get("planSource") !== "trial") return plan;
  const expires = user.get("planExpiresAt");
  if (expires instanceof Timestamp && expires.toMillis() > Date.now()) return plan;
  const before = user.get("planBeforeTrial");
  return typeof before === "string" ? before : "free";
}

// 月の区切りは日本時間で判定する
function currentPeriodJst(): string {
  const d = new Date(Date.now() + 9 * 60 * 60 * 1000);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

const quotaRef = (uid: string) => db.collection("talk_quotas").doc(uid);

function usedThisMonth(snap: DocumentSnapshot): number {
  const count = snap.get("count");
  return snap.get("period") === currentPeriodJst() && typeof count === "number" ? count : 0;
}

function isNameMissing(me: DocumentSnapshot): boolean {
  const name = me.get("name");
  if (typeof name !== "string") return true;
  const t = name.trim();
  return !t || t === "名前未設定" || t === "ユーザー";
}

// ---------------------------------------------------------------------------
// プロフィール画面の表示に必要な状態をまとめて返す
// （相手が自分をブロックしているかは「やり取りできるか」だけを返し、詳細は伝えない）
// ---------------------------------------------------------------------------
export const getProfileState = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);

  const [me, peer, myBlock, peerBlock, room, quota] = await db.getAll(
    userRef(uid),
    userRef(peerId),
    sub(uid, "blocks", peerId),
    sub(peerId, "blocks", uid),
    roomRef(uid, peerId),
    quotaRef(uid),
  );

  return {
    peerExists: peer.exists,
    iBlocked: myBlock.exists,
    canInteract: peer.exists && !myBlock.exists && !peerBlock.exists,
    hasChatHistory: room.exists,
    nameMissing: isNameMissing(me),
    monthlyLimit: talkLimitOf(effectivePlan(me)), // null = 無制限
    monthlyUsed: usedThisMonth(quota),
  };
});

// ---------------------------------------------------------------------------
// トーク開始（新しい相手なら月間の枠を1つ使い、トークルームを作る）
// すでにルームがある相手なら、枠は使わない
// ---------------------------------------------------------------------------
export const startTalk = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const peerId = peerIdOf(req, uid);
  const room = roomRef(uid, peerId);

  const consumed = await db.runTransaction(async (tx) => {
    const [me, peer, myBlock, peerBlock, roomSnap, quota] = await tx.getAll(
      userRef(uid),
      userRef(peerId),
      sub(uid, "blocks", peerId),
      sub(peerId, "blocks", uid),
      room,
      quotaRef(uid),
    );

    if (!peer.exists || myBlock.exists || peerBlock.exists) {
      throw new HttpsError("failed-precondition", "このユーザーとはやり取りできません");
    }
    if (isNameMissing(me)) {
      throw new HttpsError("failed-precondition", "先にプロフィールで名前を設定してください");
    }
    if (roomSnap.exists) return false; // 以前に話したことがある相手

    const limit = talkLimitOf(effectivePlan(me));
    if (limit !== null) {
      const used = usedThisMonth(quota);
      if (used >= limit) {
        throw new HttpsError(
          "resource-exhausted",
          `今月のトーク開始上限（${limit}人）に達しました`,
          { limit },
        );
      }
      tx.set(quotaRef(uid), { period: currentPeriodJst(), count: used + 1 });
    }

    tx.create(room, {
      users: [uid, peerId].sort(),
      lastMessage: "",
      lastMessageTime: null, // メッセージが届くまでトーク一覧には出ない
      createdAt: FieldValue.serverTimestamp(),
    });
    return limit !== null;
  });

  return { roomId: room.id, consumed };
});

// ---------------------------------------------------------------------------
// 退会（アカウントと関連データの完全削除）
//
// 他人のデータ（相手の友達一覧・いいね一覧など）から自分を消す処理は、
// アプリからは権限上できないため、すべてサーバーで行う。
// 途中で失敗しても、もう一度呼べば続きから削除できる（何度呼んでも安全）。
// ---------------------------------------------------------------------------
const STORAGE_BUCKET = "frendy-app-project.firebasestorage.app";
const BATCH_LIMIT = 300;

// 自分のサブコレクション → 相手側で対になるサブコレクション
const PAIRED_COLLECTIONS: Array<[string, string]> = [
  ["friends", "friends"],
  ["likes", "likedBy"],
  ["likedBy", "likes"],
  ["blocks", "blockedBy"],
  ["blockedBy", "blocks"],
];

// ⚠️ 移行用：旧方式で users ドキュメントの配列に入っている自分のID
const LEGACY_ARRAY_FIELDS = ["friends", "likes", "likedBy", "blockedBy", "footprints"];

// 1ステップが失敗しても、他の削除は続ける（失敗はログに残す）
async function safeStep(name: string, uid: string, fn: () => Promise<void>) {
  try {
    await fn();
  } catch (e) {
    logger.error(`退会処理の一部に失敗: ${name}`, { uid, error: String(e) });
  }
}

export const deleteAccount = onCall(
  { ...OPTS, timeoutSeconds: 540, memory: "512MiB" },
  async (req) => {
    const uid = authUid(req);
    const me = userRef(uid);
    const writer = db.bulkWriter();

    // 1. 相手側に残っている「自分」を消す（相手の友達一覧・いいねされた一覧など）
    for (const [myCol, theirCol] of PAIRED_COLLECTIONS) {
      await safeStep(`相手側の${theirCol}`, uid, async () => {
        let last: QueryDocumentSnapshot | undefined;
        for (;;) {
          let q = me.collection(myCol).orderBy(FieldPath.documentId()).select().limit(BATCH_LIMIT);
          if (last) q = q.startAfter(last);
          const snap = await q.get();
          if (snap.empty) break;
          for (const doc of snap.docs) writer.delete(sub(doc.id, theirCol, uid));
          last = snap.docs[snap.docs.length - 1];
          await writer.flush();
        }
      });
    }

    // 2. 自分が他人に付けた足跡を消す
    await safeStep("付けた足跡", uid, async () => {
      for (let round = 0; round < 1000; round++) {
        const snap = await db
          .collectionGroup("footprints")
          .where("visitorId", "==", uid)
          .select()
          .limit(BATCH_LIMIT)
          .get();
        if (snap.empty) break;
        for (const doc of snap.docs) writer.delete(doc.ref);
        await writer.flush();
      }
    });

    // 2-2. 他人の「メッセージを送ったことがある相手」の印から自分を消す（限定バッジ用）
    //      ※ 相手のバッジや人数はそのまま（一度もらったバッジは取り上げない）
    await safeStep("メッセージ相手の印", uid, async () => {
      for (let round = 0; round < 1000; round++) {
        const snap = await db
          .collectionGroup("messaged_peers")
          .where("peerId", "==", uid)
          .select()
          .limit(BATCH_LIMIT)
          .get();
        if (snap.empty) break;
        for (const doc of snap.docs) writer.delete(doc.ref);
        await writer.flush();
      }
    });

    // 3. ⚠️ 移行用：旧方式の配列から自分のIDを取り除く
    for (const field of LEGACY_ARRAY_FIELDS) {
      await safeStep(`旧配列 ${field}`, uid, async () => {
        for (let round = 0; round < 1000; round++) {
          const snap = await db
            .collection("users")
            .where(field, "array-contains", uid)
            .select()
            .limit(BATCH_LIMIT)
            .get();
          if (snap.empty) break;
          for (const doc of snap.docs) {
            writer.update(doc.ref, { [field]: FieldValue.arrayRemove(uid) });
          }
          await writer.flush();
        }
      });
    }

    // 4. 友達申請（送った・受け取った）を消す
    for (const field of ["fromId", "toId"]) {
      await safeStep(`友達申請 ${field}`, uid, async () => {
        for (let round = 0; round < 1000; round++) {
          const snap = await db
            .collection("friend_requests")
            .where(field, "==", uid)
            .select()
            .limit(BATCH_LIMIT)
            .get();
          if (snap.empty) break;
          for (const doc of snap.docs) writer.delete(doc.ref);
          await writer.flush();
        }
      });
    }

    // 5. 自分が参加しているトークルームを、メッセージごと消す
    await safeStep("トークルーム", uid, async () => {
      for (let round = 0; round < 1000; round++) {
        const snap = await db
          .collection("chat_rooms")
          .where("users", "array-contains", uid)
          .select()
          .limit(50)
          .get();
        if (snap.empty) break;
        for (const doc of snap.docs) await db.recursiveDelete(doc.ref);
      }
    });

    // 6. 招待コード・連投制限の記録を消す
    await safeStep("招待コード", uid, async () => {
      const ownerRef = db.collection("invite_owners").doc(uid);
      const owner = await ownerRef.get();
      const code = owner.get("code");
      if (typeof code === "string") writer.delete(db.collection("invite_codes").doc(code));
      writer.delete(ownerRef);
      writer.delete(db.collection("rate_limits").doc(uid));
      writer.delete(quotaRef(uid));
      // 💡 年齢確認の提出記録（画像の保存場所や確認用リンクを含む）も削除する。
      //    プライバシーポリシーの「退会時に本人確認書類を削除する」と内容をそろえるため
      writer.delete(db.collection("verification_requests").doc(uid));
      // 招待された記録（自分が招待された側）を消す
      writer.delete(db.collection("invites").doc(uid));
      await writer.flush();

      // 自分が招待した人の記録からは、自分のIDだけを消す
      // （招待された人は、年齢確認が済めば特典を受け取れるようにしておく）
      const invited = await db
        .collection("invites")
        .where("inviterUid", "==", uid)
        .select()
        .limit(1000)
        .get();
      for (const doc of invited.docs) {
        writer.update(doc.ref, { inviterUid: FieldValue.delete(), inviterDeleted: true });
      }
      await writer.flush();
    });

    await writer.close();

    // 7. 画像（プロフィール写真・本人確認書類）を消す
    const bucket = getStorage().bucket(STORAGE_BUCKET);
    for (const prefix of [`user_images/${uid}/`, `user_verifications/${uid}/`]) {
      await safeStep(`Storage ${prefix}`, uid, async () => {
        await bucket.deleteFiles({ prefix, force: true });
      });
    }

    // 8. 自分の users ドキュメントを、サブコレクション（友達・いいね等）ごと消す
    //    ※ ここは必ず成功させる（失敗したらエラーを返し、アプリから再実行してもらう）
    await db.recursiveDelete(me);

    // 9. 最後にログインアカウントを消す
    try {
      await getAuth().deleteUser(uid);
    } catch (e) {
      if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
    }

    // 通報（reports）とご意見（opinions）は、運営の対応記録として残す。
    // ※ プライバシーポリシーに「通報・お問い合わせの記録は一定期間保管する」旨を記載すること
    return { ok: true };
  },
);

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
  const plan = effectivePlan(me);
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

// ---------------------------------------------------------------------------
// 年齢確認書類の提出
// 💡 審査状況（ageVerified）はサーバーだけが書き換える。
//    アプリから書けると、自分で「承認済み」にして年齢確認をすり抜けられてしまう。
//    画像は先にアプリから Storage にアップロードし、ここで存在と形式を確認する。
// ---------------------------------------------------------------------------
const VERIFICATION_MAX_BYTES = 8 * 1024 * 1024;

export const submitVerification = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const imagePath = `user_verifications/${uid}/verification_image`;
  const file = getStorage().bucket(STORAGE_BUCKET).file(imagePath);

  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("failed-precondition", "画像が見つかりません。もう一度アップロードしてください");
  }

  const [meta] = await file.getMetadata();
  const size = Number(meta.size ?? 0);
  const contentType = String(meta.contentType ?? "");
  if (size <= 0 || size > VERIFICATION_MAX_BYTES || !contentType.startsWith("image/")) {
    throw new HttpsError("invalid-argument", "画像の形式または大きさが正しくありません");
  }

  const me = await userRef(uid).get();
  if (me.get("ageVerified") === "verified") return { status: "verified" };

  // 💡 運営が書類を確認するためのリンク（Google Cloud コンソールの画面）。
  //    プロジェクトの管理者としてログインしている人しか開けないので、
  //    リンクが他人に見られても画像は見られない。
  const projectId = process.env.GCLOUD_PROJECT ?? "frendy-app-project";
  const reviewUrl =
    `https://console.cloud.google.com/storage/browser/_details/${STORAGE_BUCKET}/${imagePath}` +
    `?project=${projectId}`;

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(db.collection("verification_requests").doc(uid), {
    imagePath,
    size,
    contentType,
    reviewUrl,
    status: "pending",
    submittedAt: now,
  });
  batch.set(
    userRef(uid),
    {
      ageVerified: "pending",
      // 💡 Firestore コンソールは項目を名前順に並べるので、
      //    「ageVerified」で始まる名前にすると ageVerified のすぐ下に表示される。
      //    運営以外が開いても画像は見られない（管理者ログインが必要なページ）。
      ageVerifiedReviewUrl: reviewUrl,
      verificationSubmittedAt: now,
      verificationRejectionReason: "",
      // 以前のバージョンで保存していた、誰でも見られる身分証のURLを消す
      verificationImageUrl: FieldValue.delete(),
    },
    { merge: true },
  );
  await batch.commit();
  return { status: "pending" };
});


// ===========================================================================
// 無料体験（新規登録のライト1ヶ月・友達招待のプレミアム1ヶ月）
// ===========================================================================
// 友達招待：2人ともプレミアム1ヶ月無料
//
// 流れ
//  1. 招待された人が redeemInviteCode でコードを入力 → invites/{自分} に記録（pending）
//  2. 招待された人の年齢確認が承認される（users.ageVerified が verified になる）
//  3. onUserAgeVerified が検知し、2人にプレミアムを30日間つける（rewarded）
//  4. expireTrials が1時間ごとに、期限が過ぎた人を体験前のプランに戻す
//
// ズル対策
//  ・特典を渡すのは「年齢確認の承認後」だけ（運営が身分証を確認した実在の人）
//  ・コード入力は登録から7日以内・1人1回まで、自分のコードは使えない
//  ・招待した人がもらえる特典は最大3回まで
//  ・プランに関する項目はすべてサーバーだけが書き込む（ルールで保護）
// ===========================================================================
const TRIAL_DAYS = 30;
const INVITE_REDEEM_WINDOW_DAYS = 7;
const INVITER_REWARD_LIMIT = 3;
const INVITE_CODE_RE = new RegExp(`^[${INVITE_ALPHABET}]{${INVITE_LENGTH}}$`);
const DAY_MS = 24 * 60 * 60 * 1000;

// プランの高さ（高いほど機能が多い）
const PLAN_RANK: Record<string, number> = { free: 0, light: 1, standard: 2, premium: 3 };
const rankOf = (plan: unknown) => (typeof plan === "string" ? PLAN_RANK[plan] ?? 0 : 0);

// 1人分の無料体験をつける（トランザクションの中で使う）
//   trialPlan … 無料で使えるようにするプラン（light：新規登録の特典 / premium：友達招待の特典）
// 戻り値：つけたら true（すでに同じか上のプランを使っている人は false）
function applyTrial(
  tx: Transaction,
  user: DocumentSnapshot,
  trialPlan: "light" | "premium",
  days: number = TRIAL_DAYS,
  extra: Record<string, unknown> = {}, // 同じ書き込みに一緒に入れる項目（同じドキュメントへの二重書き込みを避ける）
): boolean {
  if (!user.exists) return false;
  const now = Date.now();
  const plan = typeof user.get("plan") === "string" ? (user.get("plan") as string) : "free";
  const source = user.get("planSource");
  const expires = user.get("planExpiresAt");
  const expiresMs = expires instanceof Timestamp ? expires.toMillis() : 0;
  const inTrial = source === "trial" && expiresMs > now;

  if (inTrial) {
    // 今の無料体験のほうが上のプランなら、何もしない
    if (rankOf(plan) > rankOf(trialPlan)) return false;
    if (plan === trialPlan) {
      // 同じプランの無料体験中なら、期限を延ばす
      tx.update(user.ref, {
        planExpiresAt: Timestamp.fromMillis(expiresMs + days * DAY_MS),
        trialGrantedAt: FieldValue.serverTimestamp(),
        ...extra,
      });
    } else {
      // 下のプランの無料体験中（例：ライト体験中に招待でプレミアム）なら、上のプランに切り替える
      tx.update(user.ref, {
        plan: trialPlan,
        planExpiresAt: Timestamp.fromMillis(Math.max(expiresMs, now + days * DAY_MS)),
        trialGrantedAt: FieldValue.serverTimestamp(),
        ...extra,
      });
    }
    return true;
  }

  // ストアで同じか上のプランを契約中なら、つけても意味がない
  if (source !== "trial" && rankOf(plan) >= rankOf(trialPlan)) return false;

  // 体験前のプランを覚えておき、期限が来たら戻す
  const beforePlan = source === "trial" ? user.get("planBeforeTrial") ?? "free" : plan;
  const beforeSource = source === "trial" ? user.get("planSourceBeforeTrial") ?? null : source ?? null;
  tx.update(user.ref, {
    plan: trialPlan,
    planSource: "trial",
    planExpiresAt: Timestamp.fromMillis(now + days * DAY_MS),
    planBeforeTrial: beforePlan,
    planSourceBeforeTrial: beforeSource,
    trialGrantedAt: FieldValue.serverTimestamp(),
    ...extra,
  });
  return true;
}

// 招待の特典を渡す（招待された人の年齢確認が承認済みのときだけ）
async function processInviteReward(inviteeUid: string): Promise<boolean> {
  const inviteRef = db.collection("invites").doc(inviteeUid);
  return db.runTransaction(async (tx) => {
    const invite = await tx.get(inviteRef);
    if (!invite.exists || invite.get("status") !== "pending") return false;

    const inviterUid = invite.get("inviterUid");
    const hasInviter = typeof inviterUid === "string" && UID_RE.test(inviterUid);

    // 💡 読み込みはすべて書き込みの前に行う
    const reads = [tx.get(userRef(inviteeUid))];
    if (hasInviter) {
      reads.push(tx.get(userRef(inviterUid)));
      reads.push(tx.get(db.collection("invite_owners").doc(inviterUid)));
    }
    const [invitee, inviter, inviterOwner] = await Promise.all(reads);

    if (!invitee.exists || invitee.get("ageVerified") !== "verified") return false;

    const inviteeRewarded = applyTrial(tx, invitee, "premium");

    let inviterRewarded = false;
    if (hasInviter && inviter?.exists && inviterOwner) {
      const count = inviterOwner.get("rewardCount");
      const used = typeof count === "number" ? count : 0;
      if (used < INVITER_REWARD_LIMIT) {
        inviterRewarded = applyTrial(tx, inviter, "premium");
        if (inviterRewarded) {
          tx.set(inviterOwner.ref, { rewardCount: used + 1 }, { merge: true });
        }
      }
    }

    tx.update(inviteRef, {
      status: "rewarded",
      rewardedAt: FieldValue.serverTimestamp(),
      inviteeRewarded,
      inviterRewarded,
    });
    return true;
  });
}

// ---------------------------------------------------------------------------
// 新規登録の特典：登録から1ヶ月はライトプランが無料
// 💡 users/{uid} が初めて作られたときに1回だけ動く。お金はかからず、
//    1ヶ月たつと expireTrials が自動でフリープランに戻す
// ---------------------------------------------------------------------------
const WELCOME_TRIAL_DAYS = 30;

export const onUserCreated = onDocumentCreated("users/{uid}", async (event) => {
  const uid = event.params.uid;
  if (!UID_RE.test(uid)) return;
  try {
    await db.runTransaction(async (tx) => {
      const user = await tx.get(userRef(uid));
      if (!user.exists || user.get("welcomeTrialGranted") === true) return; // 2回目以降は何もしない
      const flag = { welcomeTrialGranted: true };
      const granted = applyTrial(tx, user, "light", WELCOME_TRIAL_DAYS, flag);
      if (!granted) tx.update(user.ref, flag);
    });
  } catch (e) {
    logger.error("新規登録の無料体験の付与に失敗", { uid, error: String(e) });
  }
});

// ---------------------------------------------------------------------------
// 招待コードを入力する
// ---------------------------------------------------------------------------
export const redeemInviteCode = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const raw = (req.data ?? {}).code;
  const code = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  if (!INVITE_CODE_RE.test(code)) {
    throw new HttpsError("invalid-argument", "招待コードの形式が正しくありません");
  }

  // 登録日は Firebase Authentication の記録を使う（アプリから書き換えられない）
  const authUser = await getAuth().getUser(uid);
  const createdMs = Date.parse(authUser.metadata.creationTime);
  if (!Number.isFinite(createdMs) || Date.now() - createdMs > INVITE_REDEEM_WINDOW_DAYS * DAY_MS) {
    throw new HttpsError(
      "failed-precondition",
      `招待コードは、登録から${INVITE_REDEEM_WINDOW_DAYS}日以内に入力してください`,
    );
  }

  const inviteRef = db.collection("invites").doc(uid);
  const codeRef = db.collection("invite_codes").doc(code);

  await db.runTransaction(async (tx) => {
    const [invite, codeSnap] = await tx.getAll(inviteRef, codeRef);
    if (invite.exists) throw new HttpsError("already-exists", "招待コードはすでに入力済みです");
    if (!codeSnap.exists) throw new HttpsError("not-found", "招待コードが見つかりません");

    const inviterUid = codeSnap.get("uid");
    if (typeof inviterUid !== "string" || !UID_RE.test(inviterUid)) {
      throw new HttpsError("not-found", "招待コードが見つかりません");
    }
    if (inviterUid === uid) {
      throw new HttpsError("invalid-argument", "自分の招待コードは使えません");
    }

    tx.create(inviteRef, {
      inviterUid,
      code,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  // すでに年齢確認が済んでいる人は、その場で特典を渡す
  const rewarded = await processInviteReward(uid);
  return { status: rewarded ? "rewarded" : "pending" };
});

// ---------------------------------------------------------------------------
// 年齢確認が承認されたら、招待の特典を渡す
// 💡 users の更新のたびに動くが、ageVerified が verified に変わったとき以外はすぐ終わる
// ---------------------------------------------------------------------------
export const onUserAgeVerified = onDocumentUpdated("users/{uid}", async (event) => {
  const before = event.data?.before.get("ageVerified");
  const after = event.data?.after.get("ageVerified");
  if (before === "verified" || after !== "verified") return;
  try {
    await processInviteReward(event.params.uid);
  } catch (e) {
    logger.error("招待特典の付与に失敗", { uid: event.params.uid, error: String(e) });
  }
});

// ---------------------------------------------------------------------------
// 無料体験の期限が過ぎた人を、体験前のプランに戻す（1時間ごと）
// ---------------------------------------------------------------------------
export const expireTrials = onSchedule(
  { schedule: "every 60 minutes", timeZone: "Asia/Tokyo" },
  async () => {
    for (let round = 0; round < 100; round++) {
      const snap = await db
        .collection("users")
        .where("planSource", "==", "trial")
        .where("planExpiresAt", "<=", Timestamp.now())
        .limit(400)
        .get();
      if (snap.empty) break;

      const batch = db.batch();
      for (const doc of snap.docs) {
        const beforePlan = doc.get("planBeforeTrial");
        const beforeSource = doc.get("planSourceBeforeTrial");
        batch.update(doc.ref, {
          plan: typeof beforePlan === "string" ? beforePlan : "free",
          planSource: typeof beforeSource === "string" ? beforeSource : FieldValue.delete(),
          planExpiresAt: FieldValue.delete(),
          planBeforeTrial: FieldValue.delete(),
          planSourceBeforeTrial: FieldValue.delete(),
        });
      }
      await batch.commit();
      logger.info("無料体験の期限切れを戻しました", { count: snap.size });
      if (snap.size < 400) break;
    }
  },
);