/************************************************************************
 * @description [RapidOcrOnnx](https://github.com/RapidAI/RapidOcrOnnx)
 * A cross platform OCR Library based on PaddleOCR & OnnxRuntime
 * @author thqby, RapidAI
 * @date 2024/08/07
 * @version 1.0.2
 * @license Apache-2.0
 ***********************************************************************/

class RapidOcr {
    static _dllHandle := 0
    static _initialized := false

    ptr := 0

    /**
     * @param {String} scriptDir - 脚本所在目录，通常传入 A_ScriptDir
     * @param {Integer} [mode] - 语言模式：1=中文(ch_models)，0=英文(en_models)，默认1
     * @param {Map|Object} [config] - 可选配置，覆盖默认模型路径
     *   - models: 模型目录路径
     *   - det: det模型文件名
     *   - rec: rec模型文件名
     *   - cls: cls模型文件名
     *   - keys:keys文件路径
     *   - numThread:线程数，默认2
     * @example
     * param := RapidOcr.OcrParam()
     * param.doAngle := false
     * ocr := RapidOcr.New(A_ScriptDir)
     * MsgBox ocr.ocr_from_file('1.jpg', param)
     */
    __New(scriptDir, mode := 1, config := 0) {
        ; 加载DLL
        if !RapidOcr._LoadDll(scriptDir) {
            MsgBox 'Failed to load RapidOcrOnnx.dll'
            return
        }

        ; 构建配置
        cfg := RapidOcr._BuildConfig(scriptDir, mode, config)

        ; 验证模型文件
        if !RapidOcr._ValidateModels(cfg)
            return

        ; 初始化OCR
        this.ptr := DllCall('RapidOcrOnnx\OcrInit', 'str', cfg['det_model'], 'str', cfg['cls_model'], 'str', cfg[
            'rec_model'],
            'str', cfg['keys_dict'], 'int', cfg['numThread'], 'Cdecl')
        if !this.ptr {
            MsgBox 'Failed to initialize OCR engine'
            return
        }
    }

    __Delete() {
        if this.ptr {
            DllCall('RapidOcrOnnx\OcrDestroy', 'ptr', this, 'Cdecl')
        }
    }

    ; ===== Private Methods =====

    /**
     * 加载 RapidOcrOnnx.dll
     * @param {String} scriptDir
     * @returns {Boolean} 是否成功
     */
    static _LoadDll(scriptDir) {
        if RapidOcr._dllHandle
            return true

        arch := (A_PtrSize * 8) 'bit'
        dllPath := scriptDir '\Plugins\RapidOcr\' arch '\RapidOcrOnnx.dll'

        RapidOcr._dllHandle := DllCall('LoadLibrary', 'str', dllPath, 'ptr')
        return RapidOcr._dllHandle != 0
    }

    /**
     * 构建配置对象
     * @param {String} scriptDir
     * @param {Integer} mode
     * @param {Map|Object} config
     * @returns {Map}
     */
    static _BuildConfig(scriptDir, mode, config) {
        ; 默认模型目录
        modelDir := (mode = 1 ? 'ch_models' : 'en_models')
        defaultModels := scriptDir '\Plugins\RapidOcr\' modelDir

        ; 解析传入的配置
        if !config {
            cfg := Map('models', defaultModels, 'numThread', 2)
        } else if config.Has('models') {
            cfg := config.Clone()
        } else {
            cfg := Map('models', defaultModels, 'numThread', 2)
            for k, v in (config is Map ? config : config.OwnProps())
                if k != 'models'
                    cfg[k] := v
        }

        ; 添加路径分隔符
        modelsPath := cfg['models']
        if !(modelsPath ~= '[/\\]$')
            modelsPath .= '\'
        cfg['models'] := modelsPath

        return this._FindModels(cfg)
    }

    /**
     * 自动查找模型文件
     * @param {Map} cfg
     * @returns {Map}
     */
    static _FindModels(cfg) {
        modelsPath := cfg['models']

        ; 查找keys文件
        if !cfg.Has('keys_dict') {
            loop files modelsPath '*.txt' {
                if A_LoopFileName ~= 'i)_keys|\.dict[_]' {
                    cfg['keys_dict'] := A_LoopFileFullPath
                    break
                }
            }
        }

        ; 查找onnx模型文件
        if !cfg.Has('det_model')
            cfg['det_model'] := ''
        if !cfg.Has('rec_model')
            cfg['rec_model'] := ''
        if !cfg.Has('cls_model')
            cfg['cls_model'] := ''

        loop files modelsPath '*.onnx' {
            if RegExMatch(A_LoopFileName, 'i)_(det|cls|rec)[_.]', &m) {
                key := m[1] '_model'
                if !cfg.Has(key) || !cfg[key] {
                    cfg[key] := A_LoopFileFullPath
                }
            }
            ; 找到所有必需模型后可提前退出
            if cfg['det_model'] && cfg['rec_model'] && cfg['cls_model']
                break
        }

        return cfg
    }

    /**
     * 验证模型文件
     * @param {Map} cfg
     */
    static _ValidateModels(cfg) {
        required := ['det_model', 'rec_model', 'keys_dict']
        optional := ['cls_model']

        for key in required {
            if !cfg.Has(key) || !cfg[key] {
                MsgBox 'Required model not found: ' key
                return false
            }
            if !FileExist(cfg[key]) {
                MsgBox 'Model file does not exist: ' cfg[key]
                return false
            }
        }
        return true
    }

    ; ===== Public Methods =====

    /**
     * 从Mat执行OCR
     * @param {Integer} mat
     * @param {RapidOcr.OcrParam} param
     * @param {Boolean} allresult
     * @returns {RapidOcr.OcrResult}
     */
    ocr_from_mat(mat, param := 0, allresult := false) {
        return DllCall('RapidOcrOnnx\OcrDetectMat', 'ptr', this, 'ptr', mat,
            'ptr', param, 'ptr', RapidOcr._cb(2 - !allresult), 'ptr', ObjPtr(&res), 'Cdecl Int') ? res : ''
    }

    /**
     * 从图片文件执行OCR
     * @param {String} picpath
     * @param {RapidOcr.OcrParam} param
     * @param {Boolean} allresult
     * @returns {RapidOcr.OcrResult}
     */
    ocr_from_file(picpath, param := 0, allresult := false) {
        return DllCall('RapidOcrOnnx\OcrDetectFile', 'ptr', this, 'astr',
            picpath, 'ptr', param, 'ptr', RapidOcr._cb(2 - !allresult), 'ptr', ObjPtr(&res), 'Cdecl') ? res : ''
    }

    /**
     * 从二进制数据执行OCR
     * @param {Buffer} data
     * @param {Integer} size
     * @param {RapidOcr.OcrParam} param
     * @param {Boolean} allresult
     * @returns {RapidOcr.OcrResult}
     */
    ocr_from_binary(data, size, param := 0, allresult := false) {
        return DllCall('RapidOcrOnnx\OcrDetectBinary', 'ptr', this,
            'ptr', data, 'uptr', size, 'ptr', param, 'ptr', RapidOcr._cb(2 - !allresult), 'ptr', ObjPtr(&res)) ? res :
            ''
    }

    /**
     * 从Bitmap数据执行OCR
     * @param {Buffer} data
     * @param {RapidOcr.OcrParam} param
     * @param {Boolean} allresult
     * @returns {RapidOcr.OcrResult}
     */
    ocr_from_bitmapdata(data, param := 0, allresult := false) {
        return DllCall('RapidOcrOnnx\OcrDetectBitmapData', 'ptr',
            this, 'ptr', data, 'ptr', param, 'ptr', RapidOcr._cb(2 - !allresult), 'ptr', ObjPtr(&res), 'Cdecl') ? res :
            ''
    }

    ; ===== Static Callbacks =====

    static _cb(i) {
        static cbs := [
            { ptr: CallbackCreate(get_text), __Delete: this => CallbackFree(this.ptr) }, 
            { ptr: CallbackCreate(get_result), __Delete: this => CallbackFree(this.ptr) },]
        return cbs[i]
        get_text(userdata, ptext, presult) => %ObjFromPtrAddRef(userdata)% := StrGet(ptext, 'utf-8')
        get_result(userdata, ptext, presult) {
            result := %ObjFromPtrAddRef(userdata)% := RapidOcr.OcrResult(presult)
            result.text := StrGet(ptext, 'utf-8')
            return result
        }
    }

    ; ===== Nested Classes =====

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

        ; default: 0.6
        boxScoreThresh {
            get => NumGet(this, 8, 'float')
            set => NumPut('float', Value, this, 8)
        }

        ; default: 0.3
        boxThresh {
            get => NumGet(this, 12, 'float')
            set => NumPut('float', Value, this, 12)
        }

        ; default: 2.0
        unClipRatio {
            get => NumGet(this, 16, 'float')
            set => NumPut('float', Value, this, 16)
        }

        ; default: 1
        doAngle {
            get => NumGet(this, 20, 'int')
            set => NumPut('int', Value, this, 20)
        }

        ; default: 1
        mostAngle {
            get => NumGet(this, 24, 'int')
            set => NumPut('int', Value, this, 24)
        }

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
            RapidOcr.OcrResult._read_vector(this, &ptr += 16, RapidOcr.OcrResult._read_textblock)
        }

        static _align(ptr, begin, to_align) {
            return begin + ((ptr - begin + --to_align) & ~to_align)
        }

        static _read_double(&ptr) {
            v := NumGet(ptr, 'double')
            ptr += 8
            return v
        }

        static _read_float(&ptr) {
            v := NumGet(ptr, 'float')
            ptr += 4
            return v
        }

        static _read_int(&ptr) {
            v := NumGet(ptr, 'int')
            ptr += 4
            return v
        }

        static _read_point(&ptr) {
            return { x: RapidOcr.OcrResult._read_int(&ptr), y: RapidOcr.OcrResult._read_int(&ptr) }
        }

        static _read_string(&ptr) {
            static size := 2 * A_PtrSize + 16
            sz := NumGet(ptr + 16, 'uptr')
            p := sz < 16 ? ptr : NumGet(ptr, 'ptr')
            ptr += size
            return StrGet(p, sz, 'utf-8')
        }

        static _read_vector(arr, &ptr, read_element) {
            static size := 3 * A_PtrSize
            pend := NumGet(ptr, A_PtrSize, 'ptr')
            p := NumGet(ptr, 'ptr')
            ptr += size
            while p < pend
                arr.push(read_element(&p))
            return arr
        }

        static _read_textblock(&ptr, begin) {
            ptr_bak := ptr
            return {
                boxPoint: RapidOcr.OcrResult._read_vector([], &ptr, RapidOcr.OcrResult._read_point),
                boxScore: RapidOcr.OcrResult._read_float(&ptr),
                angleIndex: RapidOcr.OcrResult._read_int(&ptr),
                angleScore: RapidOcr.OcrResult._read_float(&ptr),
                angleTime: RapidOcr.OcrResult._read_float(&ptr := RapidOcr.OcrResult._align(ptr, begin, 8)),
                text: RapidOcr.OcrResult._read_string(&ptr),
                charScores: RapidOcr.OcrResult._read_vector([], &ptr, RapidOcr.OcrResult._read_float),
                crnnTime: RapidOcr.OcrResult._read_float(&ptr := RapidOcr.OcrResult._align(ptr, begin, 8)),
                blockTime: RapidOcr.OcrResult._read_float(&ptr)
            }
        }
    }
}
