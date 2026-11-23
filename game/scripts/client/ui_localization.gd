extends RefCounted
## Russian/English interface strings built in code (no CSV import step). The English text itself is the message
## key, so every existing Label, Button and tooltip whose text matches is translated by the engine as soon as the
## locale changes (Godot auto-translate) without editing the code that creates it. Equivalent to the Unity
## Localization package string tables and Unreal's FText string tables.

const UiSettings = preload("res://scripts/client/ui_settings.gd")

const RU := {
	"PLAY SOLO": "ИГРАТЬ ОДНОМУ",
	"Join server": "Подключиться к серверу",
	"Solo survivor": "Одиночный выживший",
	"Graphics quality (Ctrl+F11 in game)": "Качество графики (Ctrl+F11 в игре)",
	"Performance": "Производительность",
	"Balanced": "Баланс",
	"High": "Высокое",
	"Ultra": "Ультра",
	"Auto (GPU-aware 3D + details)": "Авто (по возможностям GPU)",
	"Inventory (I)": "Инвентарь (I)",
	"Crafting (C)": "Крафт (C)",
	"Skills and perks (K)": "Навыки и перки (K)",
	"World map (J)": "Карта мира (J)",
	"Controls (F2)": "Управление (F2)",
	"Runs the world on this computer (every system, saved between sessions) and joins it.": "Запускает мир на этом компьютере (все системы, сохранение между сессиями) и входит в него.",
	"Paused": "Пауза",
	"Resume": "Продолжить",
	"Settings": "Настройки",
	"Gameplay": "Игра",
	"Graphics": "Графика",
	"Audio": "Звук",
	"Quality preset": "Качество графики",
	"Window mode": "Режим окна",
	"Windowed": "В окне",
	"Fullscreen": "Полный экран",
	"Vertical sync": "Вертикальная синхронизация",
	"FPS limit": "Ограничение FPS",
	"On": "Вкл.",
	"Unlimited": "Без ограничений",
	"Auto adjusts 3D resolution and details to GPU load.": "Автоматически подстраивает разрешение 3D и детализацию под нагрузку GPU.",
	"Master volume": "Общая громкость",
	"Music volume": "Громкость музыки",
	"Sound effects volume": "Громкость эффектов",
	"Interface sounds volume": "Громкость интерфейса",
	"Ambience volume": "Громкость окружения",
	"Reset sound levels": "Сбросить громкость",
	"Reset display settings": "Сбросить настройки экрана",
	"Controls": "Управление",
	"Accessibility": "Доступность",
	"Language": "Язык",
	"Toggle sprint": "Бег по нажатию (переключатель)",
	"Toggle crouch": "Приседание по нажатию (переключатель)",
	"Show FPS overlay": "Показывать FPS",
	"First-person field of view": "Угол обзора от первого лица",
	"Mouse sensitivity": "Чувствительность мыши",
	"Invert mouse Y": "Инвертировать мышь по вертикали",
	"First-person head bob": "Покачивание головы от первого лица",
	"Colorblind filter": "Фильтр для дальтоников",
	"Off": "Выкл.",
	"Protanopia": "Протанопия",
	"Deuteranopia": "Дейтеранопия",
	"Tritanopia": "Тританопия",
	"Interface scale": "Масштаб интерфейса",
	"Reduce screen shake": "Уменьшить тряску экрана",
	"Reduce flashes": "Уменьшить вспышки",
	"High-contrast interface": "Высококонтрастный интерфейс",
	"Closed captions": "Субтитры для звуков",
	"Caption size": "Размер субтитров",
	"Small": "Малый",
	"Medium": "Средний",
	"Large": "Большой",
	"Reset to defaults": "Сбросить",
	"Rebind keys: click an action, then press a key (Esc cancels).": "Назначение клавиш: нажмите на действие, затем на клавишу (Esc отмена).",
	"Press a key...": "Нажмите клавишу...",
	"Move up": "Вперёд",
	"Move down": "Назад",
	"Move left": "Влево",
	"Move right": "Вправо",
	"Sprint": "Бег",
	"Crouch": "Присесть",
	"Pause menu": "Меню паузы",
	"FPS overlay": "Счётчик FPS",
	"Interact": "Действие",
	"Inventory": "Инвентарь",
	"Attack": "Атака",
	"Loot": "Подобрать",
	"Skill": "Умение",
	"Dodge": "Уклон",
	"Craft": "Крафт",
	"Map": "Карта",
	"Skills": "Навыки",
	"Gamepad detected: on-screen prompts follow the last device used.": "Геймпад найден: подсказки следуют за последним устройством.",
	"Already used by %s: swapped.": "Уже занято действием «%s»: клавиши поменялись.",
	# Closed captions.
	"Gunshot": "Выстрел",
	"Melee swing": "Удар в ближнем бою",
	"You are hit": "Вас ударили",
	"Infected shrieks": "Заражённый визжит",
	"Infected collapses": "Заражённый падает",
	"Barricade breaks": "Баррикада ломается",
	"Trap snaps": "Сработала ловушка",
	"Flash burst": "Вспышка",
	"Thunder crack": "Раскат грома",
	"Thunder warning": "Предупреждение о грозе",
	"Impact": "Удар",
	"Chime": "Звон",
	"You die": "Вы погибли",
	"Outpost captured": "Аванпост захвачен",
	"Skill improves": "Навык вырос",
	"Crate opens": "Ящик открыт",
	"Gathered": "Собрано",
	"ahead": "впереди",
	"behind": "сзади",
	"left": "слева",
	"right": "справа",
	"ahead-left": "впереди слева",
	"ahead-right": "впереди справа",
	"behind-left": "сзади слева",
	"behind-right": "сзади справа",
	"nearby": "рядом",
}

static var _installed := false


static func detect_locale() -> String:
	var saved := str(UiSettings.get_value("locale"))
	if saved in UiSettings.LOCALES:
		return saved
	return "ru" if OS.get_locale_language() == "ru" else "en"


## Builds the Russian Translation and registers it with the TranslationServer (idempotent).
static func install() -> void:
	if _installed:
		return
	_installed = true
	var ru := Translation.new()
	ru.locale = "ru"
	for key in RU:
		ru.add_message(key, RU[key])
	TranslationServer.add_translation(ru)


static func set_locale(code: String, persist: bool = true) -> void:
	install()
	code = code if code in UiSettings.LOCALES else "en"
	TranslationServer.set_locale(code)
	UiSettings.set_value("locale", code, persist)


static func apply_saved() -> void:
	install()
	TranslationServer.set_locale(detect_locale())


## Looks a string up directly (no scene tree needed); falls back to the English key.
static func t(key: String, locale: String = "") -> String:
	if locale == "":
		locale = TranslationServer.get_locale().substr(0, 2)
	if locale == "ru" and RU.has(key):
		return RU[key]
	return key


## Entries with an empty value; used by the unit test to catch a blank translation.
static func missing_entries() -> Array:
	var bad := []
	for key in RU:
		if str(RU[key]).strip_edges() == "":
			bad.append(key)
	return bad
