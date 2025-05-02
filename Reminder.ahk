#Requires AutoHotkey v2.0
#SingleInstance Ignore

SendMode("Input")
SetWorkingDir(A_ScriptDir)

global ReminderGui := ""
global ReminderDDL := ""

; Окно напоминаний
global ReminderWindowW := 145
global ReminderWindowH := 107

; Основное окно
global ReminderW := 230
global ReminderH := 32
; global ReminderX := A_ScreenWidth - ReminderWindowW - ReminderW - 20
; global ReminderY := 190

global ReminderSlots := []  ; Массив для отслеживания занятых позиций окна

global ReminderEdit := ""
global ReminderUpDown := ""

global RemindersFile := A_ScriptDir "\reminders.ini"  ; Файл для сохранения настроек

; Проверка существования файла настроек
if (!FileExist(RemindersFile)) {
    MsgBox("Отсутствует файл настроек reminders.ini!", "Error", 16)
    ExitApp()
}

; Загружаем напоминания из файла настроек
reminders := LoadFromIni(RemindersFile, "Reminders")

; Загружаем горячую клавишу из файла настроек
key := LoadFromIni(RemindersFile, "Hotkey")

; Загружаем прозрачность окна напоминания из файла настроек
transparent := LoadFromIni(RemindersFile, "WinTransparent")

; Загружаем координаты главного окна напоминания из файла настроек
coordMainWindow := LoadFromIni(RemindersFile, "CoordinatesMainWindow")

; Получаем массив имен
names := []
for item in reminders
    names.Push(item.key)

SetupTrayMenu()

; Создаем горячую клавишу для открытия окна напоминания
Hotkey(key[1].value, (*) => showReminderGui())
return

SetupTrayMenu(*) {
    A_IconTip := "Reminder"

    ; Иконки для меню
    trayIcon := A_ScriptDir "\icons\reminder.ico"
    TraySetIcon(trayIcon, , true)

    ; Получаем объект меню трея
    trayMenu := A_TrayMenu

    ; Очищаем стандартные пункты меню
    trayMenu.Delete()

    ; Добавляем пункт "Exit" с иконкой
    trayMenu.Add("Exit", (*) => ExitApp())

    exitIcon := A_ScriptDir "\icons\exit.ico"

    ; Устанавливаем иконку для пункта Exit, если путь указан
    if (exitIcon != "") {
        try {
            trayMenu.SetIcon("Exit", exitIcon)
        } catch as e {
            MsgBox("Не удалось загрузить иконку: " e.Message, "Error", 16)
        }
    }
}

; Функция для загрузки из файла настроек
LoadFromIni(iniFile, section) {
    keys := []

    sections := IniRead(iniFile, section)
    if (!sections) {
        MsgBox("В файле настроек нет секции [" section "]", "Error", 16)
        ExitApp()
    }
    ; Разбиваем на массив строк
    sectionArray := StrSplit(sections, "`n")

    ; Для каждой строки получаем часть до знака =
    for section in sectionArray {
        if (section = "")  ; Пропускаем пустые строки
            continue

        ; Разделяем строку по первому знаку =
        parts := StrSplit(section, "=", "`"", 2)  ; Ограничиваем разделение на 2 части

        key1 := Trim(parts[1])  ; Trim удаляет лишние пробелы
        value1 := Trim(parts[2])  ; Trim удаляет лишние пробелы
        ; Получаем значение из INI
        keys.Push({ key: key1, value: value1 })
    }

    return keys
}

showReminderGui() {
    global ReminderGui, ReminderDDL, ReminderEdit, ReminderUpDown, reminders

    ; Проверяем, существует ли уже окно
    if IsObject(ReminderGui) && WinExist("Reminder ahk_class AutoHotkeyGUI") {
        ; Окно уже существует - активируем его
        ReminderGui.Show()
        ReminderGui.Restore() ; На случай, если было свернуто
        WinActivate("Reminder ahk_class AutoHotkeyGUI")
        return
    }

    ; ReminderGui := Gui("+AlwaysOnTop +ToolWindow", "Reminder")
    ReminderGui := Gui("+AlwaysOnTop", "Reminder")
    ReminderGui.OnEvent("Close", (*) => ExitApp())

    ; Добавляем элементы
    ReminderDDL := ReminderGui.Add("DropDownList", "x5 y5 vChoice Section w100", names)
    ReminderDDL.OnEvent("Change", UpdateEditField)  ; Обработчик изменения выбора

    ReminderEdit := ReminderGui.Add("Edit", "x110 y5 Right ys w45")
    ReminderUpDown := ReminderGui.Add("UpDown", "ys Range1-1000", 1)
    ReminderTxtMinute := ReminderGui.Add("Text", "x160 y10", "мин")

    ReminderBtnSave := ReminderGui.Add("Button", "x185 y5", "Save")
    ReminderBtnSave.OnEvent("Click", SaveReminder)

    ; ReminderGui.Show("x" ReminderX " y" ReminderY " w" ReminderW " h" ReminderH)
    ReminderGui.Show("x" coordMainWindow[1].value " y" coordMainWindow[2].value " w" ReminderW " h" ReminderH)
}

; Функция обновления поля Edit при изменении выбора в DDL
UpdateEditField(*) {
    selectedName := ReminderDDL.Text
    time := GetTimeByName(selectedName)
    ReminderEdit.Value := time
    ReminderUpDown.Value := time
}

; Функция поиска времени по имени
GetTimeByName(name) {
    for item in reminders {
        if (item.key = name) {
            return item.value
        }
    }
    return 0  ; Значение по умолчанию, если не найдено
}

SaveReminder(*) {
    global ReminderGui, ReminderDDL, ReminderEdit, ReminderSlots
    Choice := ReminderDDL.Text
    if (Choice = "") {
        MsgBox("Выберите напоминание!", "Error", 16)
        return
    }

    minutes := ReminderEdit.Value

    slot := FindOrCreateSlot()

    ; Рассчитываем позицию и проверяем выход за пределы экрана
    yPos := CalculateYPos(slot)
    if (yPos + ReminderWindowH > A_ScreenHeight) {
        MsgBox("Конец экрана! Невозможно создать новое напоминание.", "Attention", 48)
        return
    }

    ; Создаем окно напоминания
    CreateReminderWindow(Choice, yPos, minutes, slot)
    ReminderSlots[slot] := true  ; Помечаем слот как занятый

    ReminderGui.Hide()
}

CreateReminderWindow(title, yPos, minutes, slot) {
    global ReminderEdit, ReminderUpDown, ReminderSlots
    ; Получаем текущее время
    CurrentTime := FormatTime(A_Now, "HH:mm:ss")
    TriggerTime := FormatTime(DateAdd(A_Now, minutes, "Minutes"), "HH:mm:ss")

    ReminderWindowX := A_ScreenWidth - ReminderWindowW
    ReminderWindowY := yPos

    ; Создаем окно
    ReminderWindow := Gui("+AlwaysOnTop -Caption +ToolWindow", title)
    ReminderWindow.BackColor := "F0F0F0"

    ; Добавляем элементы
    ReminderWindow.SetFont("s12 cRed", "Arial")
    Text1 := ReminderWindow.Add("Text", "Center x5 y5 w" ReminderWindowW - 10, title)
    ReminderWindow.SetFont("")
    Text2 := ReminderWindow.Add("Text", "x5 y+5 w" ReminderWindowW - 10, "Создано: " CurrentTime)
    Text3 := ReminderWindow.Add("Text", "x5 y+5 w" ReminderWindowW - 10, "Сработает в: " TriggerTime)

    ; Добавляем счетчик обратного времени
    CountdownText := ReminderWindow.Add("Text", "x5 y+5 w" ReminderWindowW - 10, "Осталось: " minutes " мин 00 сек"
    )

    BtnClose := ReminderWindow.Add("Button", "x5 y+5 w" ReminderWindowW - 10 " h20", "Close")

    ; Делаем окно полупрозрачным
    WinSetTransparent(transparent[1].value, ReminderWindow)

    ; Позиционируем в правом верхнем углу
    ReminderWindow.Show("x" ReminderWindowX " y" ReminderWindowY " w" ReminderWindowW " h" ReminderWindowH " NoActivate"
    )

    ; Запускаем таймер обратного отсчета
    startTime := A_TickCount
    totalSeconds := minutes * 60
    SetTimer(UpdateCountdown, 1000)

    ; Функция обновления счетчика
    UpdateCountdown() {
        elapsedSeconds := (A_TickCount - startTime) // 1000
        remainingSeconds := totalSeconds - elapsedSeconds

        if (remainingSeconds <= 0) {
            CountdownText.Text := "Время вышло!"
            ReminderWindow.BackColor := "00FF00"  ; Меняем цвет на зеленый
            SetTimer(UpdateCountdown, 0)  ; Останавливаем таймер
            return
        }

        mins := remainingSeconds // 60
        secs := Mod(remainingSeconds, 60)
        CountdownText.Text := "Осталось: " mins " мин " Format("{:02}", secs) " сек"
    }

    ; Обработчик кнопки закрытия (останавливаем таймер)
    BtnClose.OnEvent("Click", CloseReminderWindow)
    CloseReminderWindow(*) {
        SetTimer(UpdateCountdown, 0)
        ReminderWindow.Destroy()
        ReminderSlots[slot] := false  ; Освобождаем слот
    }
}

FindOrCreateSlot() {
    global ReminderSlots

    ; Найти первый свободный слот
    for i, slotValue in ReminderSlots {
        if (!slotValue) {
            return i
        }
    }

    ; Если нет свободных слотов, добавляем новый
    ReminderSlots.Push(false)  ; Явно помечаем как свободный
    return ReminderSlots.Length
}

; Функция расчета Y-позиции для слота
CalculateYPos(slot) {
    baseOffset := 130
    return baseOffset + (slot - 1) * (ReminderWindowH + 5)
}
