extends Control

@onready var version_label: Label = %VersionLabel
@onready var github_url_label: RichTextLabel = %GithubURLLabel


func _ready() -> void:
	version_label.text = str(ProjectSettings.get_setting("application/config/version", ""))
	github_url_label.meta_clicked.connect(Events.website_requested.emit)
