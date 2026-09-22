import java.nio.file.*;
import java.util.*;

/** Uses the installed game's loader, not a second implementation of its merge rules. */
public class NutritionContracts {
    public static void main(String[] args) throws Exception {
        Class<?> manager = Class.forName("zombie.scripting.ScriptManager");
        var mod = manager.getDeclaredField("currentLoadFileMod");
        mod.setAccessible(true);
        mod.set(null, "pz-vanilla");
        Class<?> recipe = Class.forName("zombie.scripting.entity.components.crafting.CraftRecipe");
        Class<?> moduleClass = Class.forName("zombie.scripting.objects.ScriptModule");
        Object module = moduleClass.getConstructor().newInstance();
        moduleClass.getField("name").set(module, "Base");
        Class<?> luaCall = Class.forName(recipe.getName() + "$LuaCall");
        Class<?> mode = Class.forName("zombie.scripting.ScriptLoadMode");
        Object managerInstance = manager.getField("instance").get(null);
        ((Map) manager.getField("moduleMap").get(managerInstance)).put("Base", module);
        Class<?> collection = Class.forName("zombie.scripting.ScriptBucketCollection");
        for (var field : manager.getDeclaredFields()) {
            if (collection.isAssignableFrom(field.getType())) {
                field.setAccessible(true);
                collection.getMethod("registerModule", moduleClass).invoke(field.get(managerInstance), module);
            }
        }
        // Register the real vanilla timed actions needed by these recipes.
        Class<?> action = Class.forName("zombie.scripting.objects.TimedActionScript");
        Object bucket = moduleClass.getField("timedActionScripts").get(module);
        Class<?> bucketClass = Class.forName("zombie.scripting.ScriptBucket");
        Map actionMap = (Map) bucketClass.getMethod("getScriptMap").invoke(bucket);
        try (var paths = Files.list(Path.of(args[0]))) {
            for (Path path : paths.filter(p -> p.toString().endsWith(".action")).toList()) {
                String name = path.getFileName().toString().replace(".action", "");
                Object entry = action.getConstructor().newInstance();
                action.getMethod("setModule", moduleClass).invoke(entry, module);
                action.getMethod("Load", String.class, String.class).invoke(entry, name, Files.readString(path));
                actionMap.put(name, entry);
            }
        }
        for (String name : args[1].split(",")) {
            Object item = recipe.getConstructor().newInstance();
            recipe.getMethod("setModule", moduleClass).invoke(item, module);
            recipe.getMethod("InitLoadPP", String.class).invoke(item, name);
            var load = recipe.getMethod("Load", String.class, String.class);
            load.invoke(item, name, Files.readString(Path.of(args[0], name + ".vanilla")));
            List<?> inputs = List.copyOf((List<?>) recipe.getMethod("getInputs").invoke(item));
            List<?> outputs = List.copyOf((List<?>) recipe.getMethod("getOutputs").invoke(item));
            load.invoke(item, name, Files.readString(Path.of(args[0], name + ".overlay")));
            if (!inputs.equals(recipe.getMethod("getInputs").invoke(item)) ||
                    !outputs.equals(recipe.getMethod("getOutputs").invoke(item))) {
                throw new AssertionError(name + " changed vanilla input/output objects");
            }
            String callback = (String) recipe.getMethod("getLuaCallString", luaCall)
                .invoke(item, luaCall.getField("OnCreate").get(null));
            String expected = "NutritionMakesSense_RecipeCodeOnCreate." +
                (name.equals("CutChicken") || name.equals("CutTurkey") ? "cutPoultry" : "preserveNutrition");
            if (!expected.equals(callback)) throw new AssertionError(name + " callback=" + callback);
            recipe.getMethod("OnScriptsLoaded", mode).invoke(item, mode.getField("Init").get(null));
            System.out.println("PASS " + name + ": original IO retained; callback resolved; finalized");
        }
    }
}
