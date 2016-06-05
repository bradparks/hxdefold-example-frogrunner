package defold.support;

#if macro
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;
using haxe.macro.Tools;

class ScriptMacro {
    static function use() {
        Context.onGenerate(function(types) {
            // get path for our main lua file
            var out = Compiler.getOutput();

            // the script directory will be relative to the main file
            // TODO: make this configurable
            var outDir = Path.directory(out) + "/scripts";

            // clear the scripts output directory
            deleteRec(outDir);
            sys.FileSystem.createDirectory(outDir);

            // collect script classes
            var scriptClasses = [];
            var baseScriptMethods = null; // this will contain a map of callback method names
            for (type in types) {
                switch (type) {
                    case TInst(_.get() => cl, _):
                        switch (cl) {
                            case {pack: ["defold", "support"], name: "Script"}:
                                baseScriptMethods = new Map();
                                for (field in cl.fields.get())
                                    baseScriptMethods[field.name] = true;

                            case {superClass: {t: _.get() => {pack: ["defold", "support"], name: "Script"}, params: [tData]}}:
                                scriptClasses.push({cls: cl, data: tData});

                            default:
                        }
                    default:
                }
            }

            // no script classes? nothing to do
            if (scriptClasses.length == 0)
                return;

            // this shouldn't happen at all
            if (baseScriptMethods == null)
                throw "No base Script class found!";

            // generate scripts for our classes
            for (script in scriptClasses) {
                var cl = script.cls;

                // expose the script, so it's visible to generated script
                cl.meta.add(":expose", [], cl.pos);

                // get data properties for generating `go.property` calls, which should be in the genrated script
                var props = getProperties(script.data, cl.pos);

                // generate the script...
                var b = new StringBuf();

                // add a nice header
                var posStr = Std.string(cl.pos);
                posStr = posStr.substring(5, posStr.length - 1);
                b.add('-- Generated by Haxe, DO NOT EDIT (original source: $posStr)\n\n');

                // require the main generated lua file
                // TODO: this should be configurable!
                b.add('require "haxe.out.main"\n\n');

                // if we have data properties, generate go.property calls for them
                // TODO: more work should be done to support all types of default values
                if (props.length > 0) {
                    for (prop in props)
                        b.add('go.property("${prop.name}", ${prop.value})\n');
                    b.add("\n");
                }

                // make an instance of script
                b.add('local script = ${cl.name}.new()\n\n');

                // generate callback fields
                for (field in cl.fields.get()) {
                    // this is a callback field, if it's overriden from the base Script class
                    if (baseScriptMethods.exists(field.name)) {
                        // generate arguments
                        var args = switch (field.type) {
                            case TFun(args, _):
                                [for (arg in args) arg.name].join(", ");
                            default:
                                throw new Error("Overriden class field is not a method. This can't happen! :)", field.pos);
                        }
                        // generate callback function definition
                        b.add('function ${field.name}($args)\n\tscript:${field.name}($args)\nend\n\n');
                    }
                }

                // finally, save the generated script file, using the name of the class
                // TODO: prevent duplicating classes, allow configurable script names, lowercase the default name
                sys.io.File.saveContent('$outDir/${cl.name}.script', b.toString());
            }
        });
    }

    // this should be in the standard library
    static function deleteRec(path:String) {
        if (sys.FileSystem.isDirectory(path)) {
            for (file in sys.FileSystem.readDirectory(path))
                deleteRec('$path/$file');
            sys.FileSystem.deleteDirectory(path);
        } else {
            sys.FileSystem.deleteFile(path);
        }
    }

    static function getProperties(type:Type, pos:Position):Array<{name:String, value:String}> {
        var result = [];
        switch (type.follow()) {
            case TAnonymous(_.get() => anon):
                for (field in anon.fields) {
                    var prop = field.meta.extract("property");
                    switch (prop) {
                        case []:
                            continue;
                        case [prop]:
                            switch (prop.params) {
                                case [{expr: EConst(CInt(s) | CFloat(s))}]:
                                    result.push({name: field.name, value: s});
                                default:
                                    throw new Error("Invalid @property params", prop.pos);
                            }
                        default:
                            throw new Error("Only single @property metadata is allowed", field.pos);
                    }
                }
            default:
                throw new Error('Invalid component data type: ${type.toString()}. Should be a structure.', pos);
        }
        return result;
    }
}
#end
