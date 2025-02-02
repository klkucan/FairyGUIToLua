package {
import fairygui.editor.plugin.ICallback;
import fairygui.editor.plugin.IFairyGUIEditor;
import fairygui.editor.plugin.IPublishData;
import fairygui.editor.plugin.IPublishHandler;
import fairygui.editor.publish.gencode.GenCodeUtils;
import fairygui.editor.plugin.IEditorUIProject;

import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

public class GenLuaCode implements IPublishHandler {
    public static const FILE_MARK:String = "--This is an automatically generated class by FairyGUI. Please do not modify it.";

    public var publishData:IPublishData;
    public var stepCallback:ICallback;


    protected var projectSettings:Object;
    protected var packageFolder:File;
    protected var packageName:String = "";
    protected var packagePath:String = "";

    protected var sortedClasses:Array = [];
    protected var prefix:String = "";
    protected var fileExt:String = "";

    private var _editor:IFairyGUIEditor;

    public function GenLuaCode(editor:IFairyGUIEditor) {
        _editor = editor;
    }

    public function doExport(data:IPublishData, callback:ICallback):Boolean {

        publishData = data;
        stepCallback = callback;

        prefix = _editor.project.customProperties["lua_class_prefix"];
        if (prefix == null) {
            prefix = "";
        }
        fileExt = _editor.project.customProperties["file_extension"];
        if (fileExt == null) {
            fileExt = "lua";
        }

        clearLogFile();

        var gen_lua:String = _editor.project.customProperties["gen_lua"];
        if (gen_lua != "true") {
            return false;
        }

        init(fileExt);
//        loadTemplate("Lua");

        stepCallback.callOnSuccess();
        return true;
    }

    protected function init(fileExtName:String):void {
        var path:String = null;
        var targetFolder:File = null;
        var oldFiles:Array = null;
        var file:File = null;
        var fileContent:String = null;
        var project:Object = _editor.project;
        this.projectSettings = project.getSettings("publish");
        try {
            path = this.projectSettings.codePath;
            path = UtilsStr.formatStringByName(path, project.customProperties);
            targetFolder = new File(project.basePath).resolvePath(path);
            if (!targetFolder.exists) {
                targetFolder.createDirectory();
            } else if (!targetFolder.isDirectory) {
                stepCallback.addMsg("Invalid code path!");
                stepCallback.callOnFail();
                return;
            }
        } catch (err:Error) {
            stepCallback.addMsg("Invalid code path!");
            stepCallback.callOnFail();
            return;
        }
        this.packageName = PinYinUtils.toPinyin(publishData.targetUIPackage.name, false, false, false);
        this.packageFolder = new File(targetFolder.nativePath + File.separator + this.packageName + "_Lua");
        if (!this.projectSettings.packageName || this.projectSettings.packageName.length == 0) {
            this.packagePath = this.packageName;
        } else {
            this.packagePath = this.projectSettings.packageName + "." + this.packageName;
        }
        if (this.packageFolder.exists) {
            oldFiles = this.packageFolder.getDirectoryListing();
            for each(file in oldFiles) {
                if (!(file.isDirectory || file.extension != fileExtName)) {
                    fileContent = UtilsFile.loadString(file);
                    if (UtilsStr.startsWith(fileContent, FILE_MARK)) {
                        UtilsFile.deleteFile(file);
                    }
                }
            }
        } else {
            this.packageFolder.createDirectory();
        }
        GenCodeUtils.prepare(publishData);
        this.sortedClasses.length = 0;//清空数组
        for each(var classInfo:Object in publishData.outputClasses) {
            stepCallback.addMsg("init-> outputClasses :" + classInfo.superClassName);
            if (classInfo.superClassName == "GComponent") {
                this.sortedClasses.push(classInfo);
            }
        }

        this.sortedClasses.sortOn("classId");
    }

    protected function loadTemplate(param1:String):void {
        var _loc3_:Object = null;
        var project:Object = publishData['project'];
        var _loc2_:File = new File(project.basePath + "/template/" + param1);
        if (_loc2_.exists) {
            _loc3_ = this.loadTemplate2(_loc2_);
            if (_loc3_["Binder"] && _loc3_["Component"]) {
                this.createFile(_loc3_);
                return;
            }
        }
        _loc2_ = File.applicationDirectory.resolvePath("template/" + param1);
        _loc3_ = this.loadTemplate2(_loc2_);
        this.createFile(_loc3_);
    }

    private function loadTemplate2(param1:File):Object {
        var _loc4_:File = null;
        var _loc5_:String = null;
        var _loc2_:Array = param1.getDirectoryListing();
        var _loc3_:Object = {};
        for each(_loc4_ in _loc2_) {
            if (_loc4_.extension == "template") {
                _loc5_ = _loc4_.name.replace(".template", "");
                _loc3_[_loc5_] = UtilsFile.loadString(_loc4_);
            }
        }
        return _loc3_;
    }

    protected function createFile(param1:*):void {
        var binderName:String = null;
        var binderContext:String = null;
        var binderRequire:Array = [];
        var binderContent:Array = [];

        var className:String = null;
        var classContext:String = null;
        var classContent:Array = null;

        var childIndex:int = 0;
        var controllerIndex:int = 0;
        var transitionIndex:int = 0;

        for each(var classInfo:Object in sortedClasses) {
            className = prefix + classInfo.className;
            classContext = param1["Component"];
            classContent = [];
            childIndex = 0;
            controllerIndex = 0;
            transitionIndex = 0;

            classContext = classContext.replace("{packageName}", packagePath);
            classContext = classContext.split("{uiPkgName}").join(publishData.targetUIPackage.name);
            classContext = classContext.split("{uiResName}").join(classInfo.className);
            classContext = classContext.split("{className}").join(className);
            classContext = classContext.replace("{componentName}", classInfo.superClassName);
            classContext = classContext.replace("{uiPath}", "ui://" + publishData.targetUIPackage.id + classInfo.classId);
            for each(var memberInfo:Object in classInfo.members) {
                if (!checkIsUseDefaultName(memberInfo.name)) {
                    var memberName:String = "self." + memberInfo.name;
                    if (memberInfo.type == "Controller") {
                        if (projectSettings.getMemberByName) {
                            classContent.push("\t" + memberName + " = self:GetController(\"" + memberInfo.name + "\");");
                        } else {
                            classContent.push("\t" + memberName + " = self:GetControllerAt(" + controllerIndex + ");");
                        }
                        controllerIndex++;
                    } else if (memberInfo.type == "Transition") {
                        if (projectSettings.getMemberByName) {
                            classContent.push("\t" + memberName + " = self:GetTransition(\"" + memberInfo.name + "\");");
                        } else {
                            classContent.push("\t" + memberName + " = self:GetTransitionAt(" + transitionIndex + ");");
                        }
                        transitionIndex++;
                    } else {
                        if (projectSettings.getMemberByName) {
                            classContent.push("\t" + memberName + " = self:GetChild(\"" + memberInfo.name + "\");");
                        } else {
                            classContent.push("\t" + memberName + " = self:GetChildAt(" + childIndex + ");");
                        }
                        childIndex++;
                    }
                }
            }
            classContext = classContext.replace("{content}", classContent.join("\r\n"));
            binderRequire.push("require('" + className + "')")
            binderContent.push("fgui.register_extension(" + className + ".URL, " + className + ");");
            UtilsFile.saveString(new File(packageFolder.nativePath + File.separator + className + "." + fileExt), FILE_MARK + "\n\n" + classContext);
        }

        binderName = packageName + "Binder";
        binderContext = param1["Binder"];
        binderContext = binderContext.replace("{packageName}", packagePath);
        binderContext = binderContext.split("{className}").join(binderName);
        binderContext = binderContext.replace("{bindRequire}", binderRequire.join("\r\n"));
        binderContext = binderContext.replace("{bindContent}", binderContent.join("\r\n"));
        UtilsFile.saveString(new File(packageFolder.nativePath + File.separator + binderName + "." + fileExt), FILE_MARK + "\n\n" + binderContext);
        stepCallback.callOnSuccess();
    }

    private function checkIsUseDefaultName(name:String):Boolean {
        if (name.charAt(0) == "n" || name.charAt(0) == "c" || name.charAt(0) == "t") {
            return _isNaN(name.slice(1));
        }
        return false;
    }

    private function _isNaN(str:String):Boolean {
        if (isNaN(parseInt(str))) {
            return false;
        }
        return true;
    }

    //-------------------------输出log到文件--------------------------

    private function printLog(log:String):void {
        var path:String = getLogFilePath();
        var file:File = new File(path);
        var fileStream:FileStream = new FileStream();
        fileStream.open(file, FileMode.APPEND);
        fileStream.writeUTFBytes(log + "\n");
        fileStream.close();
    }

    private function clearLogFile():void {
        var path:String = getLogFilePath();
//        stepCallback.addMsg("clearLogFile->log file path = " + path);
        var file:File = new File(path);
        if (file.exists) {
            file.deleteFile();
        }
    }

    // 需要提前在编辑器里面设置，
    // 文件→发布设置→包设置→发布代码，这里如果是勾选全局配置则在全局配置中设置路径
    private function getLogFilePath():String {
        var project:IEditorUIProject = _editor.project;
        this.projectSettings = project.getSettings("publish");
        var path:String = this.projectSettings.codePath;
        return path + "\\log.txt";
    }
}
}
