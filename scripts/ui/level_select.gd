extends Node2D
## 舊選關場景已併入 home.gd；保留檔案以免外部工具硬編碼路徑炸掉。


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/home.tscn")
