import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart';
import 'profile_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // フィルターの状態を保持する変数
  String _selectedGender = 'すべて';
  RangeValues _ageRange = const RangeValues(20, 40);
  List<String> _selectedTags = [];

  // サンプルのタグリスト
  final List<String> _allTags = ['Flutter', 'USCPA', '愛知県', 'カフェ巡り', '製造業', 'Python'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('frendy', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- 1. 検索バーエリア ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'キーワードで検索',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.tune, color: AppColors.point), // 絞り込みアイコン
                  onPressed: () => _showFilterModal(context),
                ),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // --- 現在のフィルター条件を表示するチップ（UX向上） ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Chip(label: Text('性別: $_selectedGender'), backgroundColor: AppColors.bgblue),
                const SizedBox(width: 8),
                Chip(label: Text('年齢: ${_ageRange.start.round()}〜${_ageRange.end.round()}歳'), backgroundColor: AppColors.bgblue),
                ..._selectedTags.map((tag) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Chip(label: Text(tag), backgroundColor: AppColors.bgblue),
                )),
              ],
            ),
          ),

          // --- 2. ユーザー一覧エリア ---
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: 10,
              itemBuilder: (context, index) {
                final String name = 'ユーザー $index';
                const String hobby = 'Flutterで開発中！USCPAの勉強も頑張っています。効率化が大好きです。';
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ProfileDetailScreen(userName: name)),
                  ),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 2,
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 200, 240, 238),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                            ),
                            child: const Icon(Icons.person, size: 50, color: Colors.white),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
                          child: Text(
                            hobby,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // フィルターモーダルを表示するメソッド
  void _showFilterModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        // モーダル内の状態を管理するためのStatefulBuilder
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text('検索フィルター', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 24),

                  // 性別選択
                  const Text('性別', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: ['すべて', '女性', '男性'].map((gender) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(gender),
                        selected: _selectedGender == gender,
                        onSelected: (bool selected) {
                          setModalState(() => _selectedGender = gender);
                        },
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 24),

                  // 年齢幅
                  Text(
                    '年齢の幅: ${_ageRange.start.round()}歳 〜 ${_ageRange.end.round()}歳',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  RangeSlider(
                    values: _ageRange,
                    min: 18,
                    max: 80,
                    divisions: 62,
                    activeColor: AppColors.point,
                    onChanged: (RangeValues values) {
                      setModalState(() => _ageRange = values);
                    },
                  ),
                  const SizedBox(height: 24),

                  // タグ検索
                  const Text('タグ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 0,
                    children: _allTags.map((tag) => FilterChip(
                      label: Text(tag, style: const TextStyle(fontSize: 12)),
                      selected: _selectedTags.contains(tag),
                      onSelected: (bool selected) {
                        setModalState(() {
                          if (selected) {
                            _selectedTags.add(tag);
                          } else {
                            _selectedTags.remove(tag);
                          }
                        });
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 32),

                  // 決定ボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // 親画面（SearchScreen）を更新
                        setState(() {});
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.point,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('この条件で検索', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}