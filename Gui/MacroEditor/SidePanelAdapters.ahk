
; 侧栏宿主用：恒为逻辑树模式
class SideEditModeCon {
    __New(value := 1) {
        this._value := value
    }
    Value {
        get => this._value
        set {
            this._value := value
        }
    }
}

class SideToolMenuStub {
    Check(*) {
    }
    Uncheck(*) {
    }
    ToggleCheck(*) {
    }
}

class SideGuiFacade {
    __New(hwnd, title := "") {
        this.Hwnd := hwnd
        this.Title := title
    }
    Hide(*) {
    }
}

CreateSubGuiClickHandler(self, guiInstance) {
    clickHandler(*) {
        ; 拖拽到树里松开后，按钮还会补一个 Click——不拦的话会在插入指令之后
        ; 又弹一次「新增指令」，两个窗叠在一起，前一个就关不掉了
        if (self._dragCancelledAt && A_TickCount - self._dragCancelledAt < 400) {
            self._dragCancelledAt := 0
            return
        }
        self.OnOpenSubGui(guiInstance)
    }
    return clickHandler
}
