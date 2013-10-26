/**
   Support for running named unit tests

   To use:

   import opmix.ut;
   mixin UTInit!__MODULE__

   @UT("TestName") unittest {
   }

   Then to run: 
   rdmd [-version=specrunner] -unittest program -m MOD_RE -t TEST_RE
*/
module opmix.ut;

struct UT { string tag; }

mixin template UTInit(string modname) {
  version(unittest) {
    import std.conv;
    import std.typecons;
    import std.typetuple;
    import std.string;
    import std.traits;

    mixin("alias mod = " ~ modname ~ ";");
    alias members = TypeTuple!(__traits(allMembers, mod));

    template unitTestTag(alias f) {
      auto helper() {
        foreach(attr; __traits(getAttributes, f))
          static if(is(typeof(attr) == UT))
            return attr.tag;
        return "";
      }
      enum string unitTestTag = helper;
    }
    
    static this() {
      int unnamed = 1;
      void addTests(alias thing)() {
        alias tests = TypeTuple!(__traits(getUnitTests, thing));
        foreach( test ; tests ) {
          auto testName = unitTestTag!test;
          if(testName == "") 
            testName = text("Unamed ", unnamed++);
          testFunctions[fullyQualifiedName!mod ~ ":" ~ testName] = &test;          
        }
      }
      addTests!mod();
      import std.stdio;
      foreach( thing ; members ) {
        mixin("alias theThing = "~thing~";");
        ///////////////////////////////////////////////////////////////
        // TODO: Find out how to call addTests only for aggregates
        // Need to query thing to see if is aggregate - otherwise
        // __traits(getUnitTests) on it complains
        // addTests!thing();
      }
    }
  }
}

version(unittest) {
  import std.stdio;
  import std.algorithm;
  import std.regex;
  import std.getopt;
  import core.runtime;
  import pprint.pp;

  static void function()[string] testFunctions;

  private {
    string[] modules;
    string[] tests;
    bool unmodified;
    bool summary;
    bool help;
  }

  bool unitTester() {
    auto delim = regex(r":");
    struct TestResult { 
      string modName; 
      string testName; 
      string result; 
    }
    TestResult[] results;
    foreach( funcName ; sort(testFunctions.keys) ) {
      auto func = testFunctions[funcName];
      auto parts = split(funcName, delim);
      auto modName = parts[0];
      auto testName = parts[1];
      bool runTest = false;
      if(modules.length == 0 || any!(re => match(modName, re))(modules)) {
        if(tests.length == 0 || any!(re => match(testName, re))(tests)) {
          runTest = true;
        }
      }
      if(runTest) {
        try {
          func();
          results ~= TestResult(modName, testName, "pass");
        } catch(Exception e) {
          results ~= TestResult(modName, testName, "fail");
        }
      }
    }
    if(summary) {
      writeln("\nTest Summary");
      writeln(tp(results));
    }
    return true;
  }

  static this() {
    string[] args = Runtime.args;
    getopt(args,
           "help|h", &help,
           "module_re|m", &modules,
           "unmodified|u", &unmodified,
           "summary|s", &summary,
           "test_re|t", &tests);

    if(help) {
      writeln("
  Test Function based unit tests.

  Supported arguments:
    [module_re|m] one or more regexes to match on module names
    [test_re|m] one or more regexes to match on test function names
    [summary|s] if true will show table of summary results
    [unmodified|u] if true will without intercepting anything
                  use this to pick up unittest blocks not in of module scope
    [help|h] this message
");
      return;
    }

    if(!unmodified) {
      Runtime.moduleUnitTester(&unitTester);
    }
  }
}
