package {

import fairygui.editor.plugin.ICallback;
import fairygui.editor.plugin.IFairyGUIEditor;
import fairygui.editor.plugin.IPublishData;
import fairygui.editor.plugin.IPublishHandler;
import fairygui.editor.publish.FileTool;

import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

import fairygui.editor.plugin.IEditorUIProject;

import flash.external.ExternalInterface;

import mx.graphics.GradientEntry;
import mx.rpc.xml.SchemaTypeRegistry;

/*
   1. print info
        stepCallback.addMsg("info");
        stepCallback.callOnFail();
 */

public final class GenerateLuaCodePlugin implements IPublishHandler {
    public static const FILE_MARK:String = "--This is an automatically generated class by FairyGUI. Please do not modify it.";

    public var publishData:IPublishData;
    public var stepCallback:ICallback;


    protected var projectSettings:Object;
    protected var packageFolder:File;
    protected var packageName:String = "";
    protected var packagePath:String = "";

    protected var sortedClasses:Array = [];
    protected var prefix:String = "";

    private var _editor:IFairyGUIEditor;


    public function GenerateLuaCodePlugin(editor:IFairyGUIEditor) {
        _editor = editor;
    }

    public function doExport(data:IPublishData, callback:ICallback):Boolean {

        publishData = data;
        stepCallback = callback;

        prefix = _editor.project.customProperties["lua_class_prefix"];
        if (prefix == null) {
            prefix = "";
        }

        clearLogFile();

        var gen_lua:String = _editor.project.customProperties["gen_lua"];
        if (gen_lua != "true") {
            return false;
        }

        init("lua");
        loadTemplate("Lua");
        stepCallback.callOnSuccess();
        return true;
    }

    protected function init(fileExtName:String):void {
        var path:String = null;
        var targetFolder:File = null;
        var oldFiles:Array = null;
        var file:File = null;
        var fileContent:String = null;
        var project:IEditorUIProject = _editor.project;
        this.projectSettings = project.getSettings("publish");
        try {
            //path = this.projectSettings.codePath;
            path = _editor.project.basePath + "\\assets\\Scripts";
            //  path = UtilsStr.formatStringByName(path, project.customProperties);
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
        this.packageName = publishData.targetUIPackage.name;

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
                    fileContent = FileTool.readFileByFile(file);
                }
            }
        } else {
            this.packageFolder.createDirectory();
        }
        //GenCodeUtils.prepare(publishData);
        this.sortedClasses.length = 0;//清空数组

        for each(var classInfo:Object in publishData.outputClasses) {
            // Tsai 2019-11-11 20:23:15
            // Content: 此处的sortedClasses记录的只有GComponent，而在FGUI中一个页面也是以GComponent为单位，
            // 可以看做是一个Canvas。在生成代码时会解析GComponent中的所有元素，并将一个GComponent中的所有元素
            // 的绑定放到以GComponent name。
            if (classInfo.superClassName == "GComponent") {
                this.sortedClasses.push(classInfo);
            }
        }
        this.sortedClasses.sortOn("classId");
    }

    protected function loadTemplate(param1:String):void {
        var contentArray:Object = null;
        var project:IEditorUIProject = _editor.project;
        // Tsai 2019-11-11 15:27:15
        // 这里用directory是这个变量的本意
        // as3： File 物件代表檔案或目錄的路徑。這可能是現有檔案或目錄，或是尚未存在的檔案或目錄
        var directory:File = new File(project.basePath + "/template/" + param1);
        if (directory.exists) {
            contentArray = this.loadTemplate2(directory);
            if (contentArray["Lua"]) {
                this.createFile(contentArray);
                return;
            }
        }

        // File.applicationDirectory得到是当前编辑器的路径
        directory = File.applicationDirectory.resolvePath("template/" + param1);
        // Tsai 2019-11-11 15:26:52
        // Content: 现在用的模板来自 https://github.com/qufangliu/Plugin_FairyGUI_Lua/tree/master/out
        contentArray = this.loadTemplate2(directory);
        this.createFile(contentArray);
    }

    private function loadTemplate2(param1:File):Object {
        var templateFile:File = null;
        var fileName:String = null;
        var templateFiles:Array = param1.getDirectoryListing();
        var contents:Object = {};
        for each(templateFile in templateFiles) {
            if (templateFile.extension == "template") {
                fileName = templateFile.name.replace(".template", "");
                contents[fileName] = FileTool.readFileByFile(templateFile);
            }
        }
        return contents;
    }

    // 生成lua文件
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
//            stepCallback.addMsg("TSAI 0 -- " + classInfo.className);
            className = /*prefix +*/ classInfo.className;
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
                            classContent.push("\t" + memberName + " = UIHelper.GetController(self.unityObject," + controllerIndex + ");");
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
                            classContent.push("\t" + memberName + " = UIHelper.GetChild(self.unityObject," + childIndex + ");");
                            if (memberInfo.type == "GButton") {
                                classContent.push("\t" + "UIHelper.BindOnClickEvent(" + memberName + ",function() " + memberInfo.name + "OnClickCallBack(self) end)");
                            }
                        }
                        childIndex++;
                    }
                }
            }
            classContent.push("--\t<CODE-GENERATE>{OnOpen}\n" + "--\t</CODE-GENERATE>{OnOpen}\n")
            classContext = classContext.replace("{content}", classContent.join("\r\n"));
            classContext = classContext + "\r\n\r\n";
            for each(var _memberInfo:Object in classInfo.members) {

                var str:String = WriteOnClickFunc(_memberInfo);
                classContext = classContext + str;
            }

            classContext = classContext + "--\t<CODE-USERAREA>{user_area}\n" + "--\t</CODE-USERAREA>{user_area}\n";

            /*binderRequire.push("require('"+ className +"')")
            binderContent.push("fgui.register_extension(" + className + ".URL, " + className + ");");*/
            var path:String = packageFolder.nativePath + File.separator + className + ".lua";
            FileTool.writeFile(path, FILE_MARK + "\n\n" + classContext);
            //  UtilsFile.saveString(new File(packageFolder.nativePath + File.separator + className + ".lua"), FILE_MARK + "\n\n" + classContext);
        }

        /*binderName = packageName + "Binder";
        binderContext = param1["Binder"];
        binderContext = binderContext.replace("{packageName}", packagePath);
        binderContext = binderContext.split("{className}").join(binderName);
        binderContext = binderContext.replace("{bindRequire}", binderRequire.join("\r\n"));
        binderContext = binderContext.replace("{bindContent}", binderContent.join("\r\n"));
        UtilsFile.saveString(new File(packageFolder.nativePath + File.separator + binderName + ".lua"), FILE_MARK + "\n\n" + binderContext);*/
        stepCallback.callOnSuccess();
    }

    private function WriteOnClickFunc(_memberInfo:Object):String {
        var str:String = "";
        if (_memberInfo.type == "GComponent") {
            var funcName:String = _memberInfo.name + "OnClickCallBack";
            str = str + "function " + funcName + "(self)\r\n" +
                    "--\t<CODE-GENERATE>{" + funcName + "}\r\n" +
                    "--\t</CODE-GENERATE>{" + funcName + "}\r\n" +
                    "end\r\n\r\n"
        }
        return str;
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