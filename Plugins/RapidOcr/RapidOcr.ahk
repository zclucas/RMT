/************************************************************************
 * @description [RapidOcrOnnx](https://github.com/RapidAI/RapidOcrOnnx)
 * A cross platform OCR Library based on PaddleOCR & OnnxRuntime
 * @author thqby, RapidAI
 * @date 2024/08/07
 * @version 1.0.2
 * @license Apache-2.0
 ***********************************************************************/

class RapidOcr {
    ptr := 0
    static dllModule := 0
    static instanceCount := 0
    /**
     * @param {Map|Object} config Set det, rec, cls model location path, keys.txt path, thread number.
     * @param {String} [config.models] dir of model files
     * @param {String} [config.det] model file name of det
     * @param {String} [config.rec] model file name of rec
     * @param {String} [config.keys] keys file name
     * @param {String} [config.cls] model file name of cls
     * @param {Integer} [config.numThread] The thread number, default: 2
     * @param {String} dllpath The path of RapidOcrOnnx.dll
     * @example
     * param := RapidOcr.OcrParam()
     * param.doAngle := false ;, param.maxSideLen := 300
     * ocr := RapidOcr({ models: A_ScriptDir '\models' })
     * MsgBox ocr.ocr_from_file('1.jpg', param)
     */
    __New(path, mode := 1) {
        modelDire := mode := 1 ? "ch_models" : "en_models"
        config := { models: path "\Plugins\RapidOcr\" modelDire }
        dllpath := path "\Plugins\RapidOcr\" (A_PtrSize * 8) "bit\RapidOcrOnnx.dll"
        if (!RapidOcr.dllModule) {
            RapidOcr.dllModule := DllCall('LoadLibrary', 'str', dllpath ?? A_LineFile '\..\' (A_PtrSize * 8) 'bit\RapidOcrOnnx.dll',
            'ptr')
            if (!RapidOcr.dllModule) {
                return
            }
        }
        if !IsSet(config)
            config := { models: A_LineFile '\..\models' }
        else if !HasProp(config, 'models')
            config.models := A_LineFile '\..\models'
        if !FileExist(config.models)
            config.models := unset
        det_model := cls_model := rec_model := keys_dict := '', numThread := 2
        for k, v in (config is Map ? config : config.OwnProps()) {
            switch k, false {
                case 'det', 'cls', 'rec': %k%_model := v
                case 'keys', 'dict': keys_dict := v
                case 'det_model', 'cls_model', 'rec_model', 'keys_dict', 'numThread': %k% := v
                case 'models', 'modelpath':
                    if !(v ~= '[/\\]$')
                        v .= '\'
                    if !keys_dict {
                        loop files v '*.txt'
                            if A_LoopFileName ~= 'i)_(keys|dict)[_.]' {
                                keys_dict := A_LoopFileFullPath
                                break
                            }
                    }
                    loop files v '*.onnx' {
                        if RegExMatch(A_LoopFileName, 'i)_(det|cls|rec)[_.]', &m) && !%m[1]%_model
                            %m[1]%_model := A_LoopFileFullPath
                    } until det_model && cls_model && rec_model
            }
        }
        for k in ['keys_dict', 'det_model', 'cls_model', 'rec_model']
            if !%k% {
                if k != 'cls_model'
                    throw ValueError('No value is specified: ' k)
            } else if !FileExist(%k%)
                throw TargetError('file "' k '" does not exist')

        this.ptr := DllCall('RapidOcrOnnx\OcrInit', 'str', det_model, 'str', cls_model, 'str', rec_model, 'str',
            keys_dict, 'int', numThread, 'Cdecl')
        if (this.ptr)
            RapidOcr.instanceCount++
    }
    __Delete() => this.ptr && RapidOcr._releaseInstance(this)

    Destroy() {
        if (this.ptr) {
            RapidOcr._releaseInstance(this)
            this.ptr := 0
        }
    }

    static _releaseInstance(instance) {
        DllCall('RapidOcrOnnx\OcrDestroy', 'ptr', instance, 'Cdecl')
        RapidOcr.instanceCount--
        if (RapidOcr.instanceCount <= 0 && RapidOcr.dllModule) {
            DllCall('FreeLibrary', 'ptr', RapidOcr.dllModule)
            RapidOcr.dllModule := 0
            RapidOcr.instanceCount := 0
        }
    }

    static __cb(i) {
        static cbs := [{ ptr: CallbackCreate(get_text), __Delete: this => CallbackFree(this.ptr) }, { ptr: CallbackCreate(
            get_result), __Delete: this => CallbackFree(this.ptr) },]
        return cbs[i]
        get_text(userdata, ptext, presult) => %ObjFromPtrAddRef(userdata)% := StrGet(ptext, 'utf-8')
        get_result(userdata, ptext, presult) {
            result := %ObjFromPtrAddRef(userdata)% := RapidOcr.OcrResult(presult)
            result.text := StrGet(ptext, 'utf-8')
            return result
        }
    }

    ; opencv4.8.0 Mat
    ocr_from_mat(mat, param := 0, allresult := false) => DllCall('RapidOcrOnnx\OcrDetectMat', 'ptr', this, 'ptr', mat,
        'ptr', param, 'ptr', RapidOcr.__cb(2 - !allresult), 'ptr', ObjPtr(&res), 'Cdecl Int') ? res : ''

    ; path of pic
    ocr_from_file(picpath, param := 0, allresult := false) => DllCall('RapidOcrOnnx\OcrDetectFile', 'ptr', this, 'astr',
        picpath, 'ptr', param, 'ptr', RapidOcr.__cb(2 - !allresult), 'ptr', ObjPtr(&res), 'Cdecl') ? res : ''

    ; Image binary data
    ocr_from_binary(data, size, param := 0, allresult := false) => DllCall('RapidOcrOnnx\OcrDetectBinary', 'ptr', this,
        'ptr', data, 'uptr', size, 'ptr', param, 'ptr', RapidOcr.__cb(2 - !allresult), 'ptr', ObjPtr(&res)) ? res : ''

    ; `struct BITMAP_DATA { void *bits; uint pitch; int width, height, bytespixel;};`
    ocr_from_bitmapdata(data, param := 0, allresult := false) => DllCall('RapidOcrOnnx\OcrDetectBitmapData', 'ptr',
        this, 'ptr', data, 'ptr', param, 'ptr', RapidOcr.__cb(2 - !allresult), 'ptr', ObjPtr(&res), 'Cdecl') ? res : ''

    class OcrParam extends Buffer {
        __New(param?) {
            super.__New(42, 0)
            p := NumPut('int', 50, 'int', 1024, 'float', 0.6, 'float', 0.3, 'float', 2.0, this)
            if !IsSet(param)
                return NumPut('int', 1, 'int', 1, p)
            for k, v in (param is Map ? param : param.OwnProps())
                if this.Base.HasOwnProp(k)
                    this.%k% := v
        }
        ; default: 50
        padding {
            get => NumGet(this, 0, 'int')
            set => NumPut('int', Value, this, 0)
        }
        ; default: 1024
        maxSideLen {
            get => NumGet(this, 4, 'int')
            set => NumPut('int', Value, this, 4)
        }
        ; default: 0.5
        boxScoreThresh {
            get => NumGet(this, 8, 'float')
            set => NumPut('float', Value, this, 8)
        }
        ; default: 0.3
        boxThresh {
            get => NumGet(this, 12, 'float')
            set => NumPut('float', Value, this, 12)
        }
        ; default: 1.6
        unClipRatio {
            get => NumGet(this, 16, 'float')
            set => NumPut('float', Value, this, 16)
        }
        ; default: false
        doAngle {
            get => NumGet(this, 20, 'int')
            set => NumPut('int', Value, this, 20)
        }
        ; default: false
        mostAngle {
            get => NumGet(this, 24, 'int')
            set => NumPut('int', Value, this, 24)
        }
        ; Output path of image with the boxes
        outputPath {
            get => StrGet(NumGet(this, 24 + A_PtrSize, 'ptr') || StrPtr(''), 'cp0')
            set => (StrPut(Value, this.__outputbuf := Buffer(StrPut(Value, 'cp0')), 'cp0'), NumPut('ptr', this.__outputbuf
                .Ptr, this, 24 + A_PtrSize))
        }
    }

    class OcrResult extends Array {
        __New(ptr) {
            this.dbNetTime := NumGet(ptr, 'double')
            this.detectTime := NumGet(ptr, 8, 'double')
            read_vector(this, &ptr += 16, read_textblock)
            align(ptr, begin, to_align) => begin + ((ptr - begin + --to_align) & ~to_align)
            read_textblock(&ptr, begin := ptr) => {
                boxPoint: read_vector([], &ptr, read_point),
                boxScore: read_float(&ptr),
                angleIndex: read_int(&ptr),
                angleScore: read_float(&ptr),
                angleTime: read_double(&ptr := align(ptr, begin, 8)),
                text: read_string(&ptr),
                charScores: read_vector([], &ptr, read_float),
                crnnTime: read_double(&ptr := align(ptr, begin, 8)),
                blockTime: read_double(&ptr)
            }
            read_double(&ptr) => (v := NumGet(ptr, 'double'), ptr += 8, v)
            read_float(&ptr) => (v := NumGet(ptr, 'float'), ptr += 4, v)
            read_int(&ptr) => (v := NumGet(ptr, 'int'), ptr += 4, v)
            read_point(&ptr) => { x: read_int(&ptr), y: read_int(&ptr) }
            read_string(&ptr) {
                static size := 2 * A_PtrSize + 16
                sz := NumGet(ptr + 16, 'uptr'), p := sz < 16 ? ptr : NumGet(ptr, 'ptr'), ptr += size
                s := StrGet(p, sz, 'utf-8')
                return s
            }
            read_vector(arr, &ptr, read_element) {
                static size := 3 * A_PtrSize
                pend := NumGet(ptr, A_PtrSize, 'ptr'), p := NumGet(ptr, 'ptr'), ptr += size
                while p < pend
                    arr.Push(read_element(&p))
                return arr
            }
        }
    }
}
