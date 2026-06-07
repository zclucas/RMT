class AutoHotInterception {
	_contextManagers := Map()

	__New() {
		bitness := A_PtrSize == 8 ? "x64" : "x86"
		baseDir := IsSet(AHIDllDir) ? AHIDllDir : A_LineFile "\.."

		interceptionDllName := "interception.dll"
		interceptionDllFile := baseDir "\" bitness "\" interceptionDllName

		if (!FileExist(interceptionDllFile)) {
			MsgBox("Unable to find " interceptionDllFile "`n`nExpected path:`n" interceptionDllFile "`n`nPlease ensure the file exists.")
			ExitApp
		}

		hModule := DllCall("LoadLibrary", "Str", interceptionDllFile, "Ptr")
		if (hModule == 0) {
			this_bitness := A_PtrSize == 8 ? "64-bit" : "32-bit"
			other_bitness := A_PtrSize == 4 ? "64-bit" : "32-bit"
			MsgBox("Bitness of " interceptionDllName " does not match bitness of AHK.`nAHK is " this_bitness ", but " interceptionDllName " is " other_bitness ".")
			ExitApp
		}
		DllCall("FreeLibrary", "Ptr", hModule)

		ahiDllName := "AutoHotInterception.dll"
		ahiDllFile := baseDir "\" ahiDllName

		if (!FileExist(ahiDllFile)) {
			MsgBox("Unable to find " ahiDllFile "`n`nExpected path:`n" ahiDllFile "`n`nPlease ensure the file exists.")
			ExitApp
		}

		hintMessage := "Try right-clicking " ahiDllFile ", select Properties, and if there is an 'Unblock' checkbox, tick it."

		asm := CLR_LoadLibrary(ahiDllFile)
		try {
			this.Instance := asm.CreateInstance("AutoHotInterception.Manager")
		}
		catch {
			MsgBox(ahiDllName " failed to load`n`n" hintMessage)
			ExitApp
		}
		if (this.Instance.OkCheck() != "OK") {
			MsgBox(ahiDllName " loaded but check failed!`n`n" hintMessage)
			ExitApp
		}
	}

	GetInstance() {
		return this.Instance
	}

	; --------------- Input Synthesis ----------------
	SendKeyEvent(id, code, state) {
		this.Instance.SendKeyEvent(id, code, state)
	}

	SendMouseButtonEvent(id, btn, state) {
		this.Instance.SendMouseButtonEvent(id, btn, state)
	}

	SendMouseButtonEventAbsolute(id, btn, state, x, y) {
		this.Instance.SendMouseButtonEventAbsolute(id, btn, state, x, y)
	}

	SendMouseMove(id, x, y) {
		this.Instance.SendMouseMove(id, x, y)
	}

	SendMouseMoveRelative(id, x, y) {
		this.Instance.SendMouseMoveRelative(id, x, y)
	}

	SendMouseMoveAbsolute(id, x, y) {
		this.Instance.SendMouseMoveAbsolute(id, x, y)
	}

	SetState(state) {
		this.Instance.SetState(state)
	}

	MoveCursor(x, y, cm := "Screen", mouseId := -1) {
		if (mouseId == -1)
			mouseId := 11 ; Use 1st found mouse
		oldMode := A_CoordModeMouse
		CoordMode("Mouse", cm)
		Loop {
			MouseGetPos(&cx, &cy)
			dx := this.GetDirection(cx, x)
			dy := this.GetDirection(cy, y)
			if (dx == 0 && dy == 0)
				break
			this.SendMouseMove(mouseId, dx, dy)
		}
		CoordMode("Mouse", oldMode)
	}

	GetDirection(cp, dp) {
		d := dp - cp
		if (d > 0)
			return 1
		if (d < 0)
			return -1
		return 0
	}

	; --------------- Querying ------------------------
	GetDeviceId(IsMouse, VID, PID, instance := 1) {
		static devType := Map(0, "Keyboard", 1, "Mouse")
		dev := this.Instance.GetDeviceId(IsMouse, VID, PID, instance)
		if (dev == 0) {
			MsgBox("Could not get " devType[isMouse] " with VID " VID ", PID " PID ", Instance " instance)
			ExitApp
		}
		return dev
	}

	GetDeviceIdFromHandle(isMouse, handle, instance := 1) {
		static devType := Map(0, "Keyboard", 1, "Mouse")
		dev := this.Instance.GetDeviceIdFromHandle(isMouse, handle, instance)
		if (dev == 0) {
			MsgBox("Could not get " devType[isMouse] " with Handle " handle ", Instance " instance)
			ExitApp
		}
		return dev
	}

	GetKeyboardId(VID, PID, instance := 1) {
		return this.GetDeviceId(false, VID, PID, instance)
	}

	GetMouseId(VID, PID, instance := 1) {
		return this.GetDeviceId(true, VID, PID, instance)
	}

	GetKeyboardIdFromHandle(handle, instance := 1) {
		return this.GetDeviceIdFromHandle(false, handle, instance)
	}

	GetMouseIdFromHandle(handle, instance := 1) {
		return this.GetDeviceIdFromHandle(true, handle, instance)
	}

	GetDeviceList() {
		DeviceList := Map()
		arr := this.Instance.GetDeviceList()
		for v in arr {
			DeviceList[v.id] := { ID: v.id, VID: v.vid, PID: v.pid, IsMouse: v.IsMouse, Handle: v.Handle }
		}
		return DeviceList
	}

	; ---------------------- Subscription Mode ----------------------
	SubscribeKey(id, code, block, callback, concurrent := false) {
		this.Instance.SubscribeKey(id, code, block, callback, concurrent)
	}

	UnsubscribeKey(id, code) {
		this.Instance.UnsubscribeKey(id, code)
	}

	SubscribeKeyboard(id, block, callback, concurrent := false) {
		this.Instance.SubscribeKeyboard(id, block, callback, concurrent)
	}

	UnsubscribeKeyboard(id) {
		this.Instance.UnsubscribeKeyboard(id)
	}

	SubscribeMouseButton(id, btn, block, callback, concurrent := false) {
		this.Instance.SubscribeMouseButton(id, btn, block, callback, concurrent)
	}

	UnsubscribeMouseButton(id, btn) {
		this.Instance.UnsubscribeMouseButton(id, btn)
	}

	SubscribeMouseButtons(id, block, callback, concurrent := false) {
		this.Instance.SubscribeMouseButtons(id, block, callback, concurrent)
	}

	UnsubscribeMouseButtons(id) {
		this.Instance.UnsubscribeMouseButtons(id)
	}

	SubscribeMouseMove(id, block, callback, concurrent := false) {
		this.Instance.SubscribeMouseMove(id, block, callback, concurrent)
	}

	UnsubscribeMouseMove(id) {
		this.Instance.UnsubscribeMouseMove(id)
	}

	SubscribeMouseMoveRelative(id, block, callback, concurrent := false) {
		this.Instance.SubscribeMouseMoveRelative(id, block, callback, concurrent)
	}

	UnsubscribeMouseMoveRelative(id) {
		this.Instance.UnsubscribeMouseMoveRelative(id)
	}

	SubscribeMouseMoveAbsolute(id, block, callback, concurrent := false) {
		this.Instance.SubscribeMouseMoveAbsolute(id, block, callback, concurrent)
	}

	UnsubscribeMouseMoveAbsolute(id) {
		this.Instance.UnsubscribeMouseMoveAbsolute(id)
	}

	; ------------- Context Mode ----------------
	CreateContextManager(id) {
		if (this._contextManagers.Has(id)) {
			Msgbox("ID " id " already has a Context Manager")
			ExitApp
		}
		cm := AutoHotInterception.ContextManager(this, id)
		this._contextManagers[id] := cm
		return cm
	}

	RemoveContextManager(id) {
		if (!this._contextManagers.Has(id)) {
			Msgbox("ID " id " does not have a Context Manager")
			ExitApp
		}
		this._contextManagers[id].Remove()
		this._contextManagers.Delete(id)
	}

	class ContextManager {
		IsActive := 0
		__New(parent, id) {
			this.parent := parent
			this.id := id
			result := this.parent.Instance.SetContextCallback(id, this.OnContextCallback.Bind(this))
		}

		OnContextCallback(state) {
			Sleep 0
			this.IsActive := state
		}

		Remove() {
			this.parent.Instance.RemoveContextCallback(this.id)
		}
	}
}
