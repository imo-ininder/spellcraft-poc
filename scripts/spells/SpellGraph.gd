class_name SpellGraph
extends Resource

## 一整張元素的法術圖譜（docs/DEMO_PLAN.md §4）。目前只有火系一張（resources/spells/fire/
## fire_graph.tres），這次 Demo 範圍不處理多元素/切換元素（docs/GDD.md §6 待定），
## Player.gd 直接 preload 這一張，不需要總表/選擇機制。

@export var start_node_id: String
@export var nodes: Array[SpellGraphNode] = []

## 線性搜尋：這張圖目前只有個位數節點，沒有優化成 id->node 的 Dictionary 快取的必要，
## 之後節點數量真的多到有感再回來改，不要先做這個優化。
func get_node_by_id(id: String) -> SpellGraphNode:
	for node in nodes:
		if node.id == id:
			return node
	return null
