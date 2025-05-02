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

global NextWindowY := 130  ; Начальная позиция первого окна
global WindowSpacing := 5  ; Отступ между окнами
global AddSpace := NextWindowY - (ReminderWindowH + WindowSpacing)

; Глобальные переменные для плавного перемещения
global targetY := 0
global currentWindow := ""

; Добавляем глобальные переменные для анимации
global AnimationSteps := 10    ; Количество шагов анимации
global AnimationSpeed := 20    ; Задержка между шагами (мс)

global ReminderSlots := []  ; Массив для отслеживания занятых позиций окна
global ActiveReminders := []  ; Массив для отслеживания активных окон напоминаний

global ReminderEdit := ""
global ReminderUpDown := ""

global RemindersFile := A_ScriptDir "\reminders.ini"  ; Файл для сохранения настроек

; global ActiveReminders := Map()  ; Хранит окна напоминаний (ключ - HWND, значение - позиция Y)

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

    ; Создаем окно напоминания
    CreateReminderWindow(Choice, minutes)

    ReminderGui.Hide()
}

CreateReminderWindow(title, minutes) {
    global ReminderEdit, ReminderUpDown, ReminderSlots, ActiveReminders
    ; Получаем текущее время
    CurrentTime := FormatTime(A_Now, "HH:mm:ss")
    TriggerTime := FormatTime(DateAdd(A_Now, minutes, "Minutes"), "HH:mm:ss")

    ReminderWindowX := A_ScreenWidth - ReminderWindowW
    ReminderWindowY := GetNextWindowY()

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

        ; Получаем текущую позицию окна
        ReminderWindow.GetPos(&x, &y)

        ; Находим индекс удаляемого окна
        removedIndex := FindReminderIndex(ReminderWindow)
        if (removedIndex = -1) {
            ReminderWindow.Destroy()
            return
        }

        ; Удаляем окно из массивов
        ActiveReminders.RemoveAt(removedIndex)
        ReminderSlots[removedIndex] := false

        ; Запускаем плавное перемещение окон
        AnimateWindowMovement(removedIndex)

        ; Уничтожаем окно после небольшой задержки
        SetTimer(() => ReminderWindow.Destroy(), -100)
    }

    ; Добавляем информацию об окне в массив активных окон
    ActiveReminders.Push({ window: ReminderWindow, slot: ReminderSlots.Length })
    ReminderSlots.Push(true)  ; Помечаем слот как занятый
}

; Функция для поиска индекса окна в массиве активных окон
FindReminderIndex(window) {
    for i, reminder in ActiveReminders {
        if (reminder.window == window) {
            return i
        }
    }
    return -1
}

; Функция для получения Y-позиции для нового окна
GetNextWindowY() {
    global ReminderWindowH, ActiveReminders, WindowSpacing, NextWindowY
    if (ActiveReminders.Length > 0) {
        lastReminder := ActiveReminders[ActiveReminders.Length]
        lastReminder.window.GetPos(&x, &y)
        return y + ReminderWindowH + WindowSpacing
    }
    return NextWindowY
}

; Новая функция для плавного перемещения окон
AnimateWindowMovement(removedIndex) {
    global ActiveReminders, ReminderWindowH, WindowSpacing, AnimationSteps, AnimationSpeed

    ; Собираем окна, которые нужно переместить (те, что ниже удаленного)
    windowsToMove := []
    for i, reminder in ActiveReminders {
        if (i >= removedIndex) {
            ; Получаем текущую и целевую позиции
            reminder.window.GetPos(&x, &currentY)
            targetY := AddSpace + i * (ReminderWindowH + WindowSpacing)
            windowsToMove.Push({ window: reminder.window, currentY: currentY, targetY: targetY })
        }
    }

    ; Если нечего перемещать, выходим
    if (windowsToMove.Length = 0)
        return

    ; Вычисляем шаг перемещения для каждого окна
    for window in windowsToMove {
        window.step := (window.targetY - window.currentY) / AnimationSteps
    }

    ; Запускаем анимацию
    SetTimer(AnimationTick, AnimationSpeed)

    ; Функция-обработчик анимации
    AnimationTick() {
        static stepsDone := 0

        ; Перемещаем все окна на один шаг
        for window in windowsToMove {
            window.currentY += window.step
            window.window.Move(, window.currentY)
        }

        stepsDone++

        ; Если анимация завершена
        if (stepsDone >= AnimationSteps) {
            SetTimer(, 0) ; Останавливаем таймер
            stepsDone := 0

            ; Финализируем позиции (на случай накопления ошибок округления)
            for window in windowsToMove {
                window.window.Move(, window.targetY)
            }
        }
    }
}
