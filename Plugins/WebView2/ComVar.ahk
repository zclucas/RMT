; Construction and deconstruction VARIANT struct
class ComVar extends Buffer {
	/**
	 * Construction VARIANT struct, `ptr` property points to the address, `__Item` property returns var's Value
	 * @param vVal Values that need to be wrapped, supports String, Integer, Double, Array, ComValue, ComObjArray
	 * ### example
	 * `var1 := ComVar('string'), MsgBox(var1[])`
	 * 
	 * `var2 := ComVar([1,2,3,4], , true)`
	 * 
	 * `var3 := ComVar(ComValue(0xb, -1))`
	 * @param vType Variant's type, VT_VARIANT(default)
	 * @param convert Convert AHK's array to ComObjArray
	 */
	static Call(vVal := 0, vType := 0xC, convert := false) {
		static size := 8 + 2 * A_PtrSize
		if vVal is ComVar
			return vVal
		var := super(size, 0), IsObject(vVal) && vType := 0xC
		var.ref := ref := ComValue(0x4000 | vType, var.Ptr + (vType = 0xC ? 0 : 8))
		if convert && (vVal is Array) {
			switch Type(vVal[1]) {
				case "Integer": vType := 3
				case "String": vType := 8
				case "Float": vType := 5
				case "ComValue", "ComObject": vType := ComObjType(vVal[1])
				default: vType := 0xC
			}
			ComObjFlags(ref[] := obj := ComObjArray(vType, vVal.Length), i := -1)
			for v in vVal
				obj[++i] := v
		} else ref[] := vVal
		if vType & 0xC
			var.IsVariant := 1
		return var
	}
	__Delete() => DllCall("oleaut32\VariantClear", "ptr", this)
	__Item {
		get => this.ref[]
		set => this.ref[] := Value
	}
	Type {
		get => NumGet(this, "ushort")
		set {
			if (!this.IsVariant)
				throw PropertyError("VarType is not VT_VARIANT, Type is read-only.", -2)
			NumPut("ushort", Value, this)
		}
	}
	static Prototype.IsVariant := 0
	static Prototype.ref := 0
}