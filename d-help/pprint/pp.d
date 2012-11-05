/**
   Functions for pretty printing data
*/

module pprint.pp;

import std.array;
import std.conv;
import std.stdio;
import std.traits;


// custom <dmodule pp public_section>

/**
   Print contents of $(D t) to the appender $(D appender).

   Params:
    T = Type of item printed
    A = Type of appender
    indent = Amount to indent each level
    cum_indent = Current cumulative indentation
    trailer = How to end out each finished element

    appender = Add string representation of item to this
    item = Item to dump into appender
 */
private void print(T, A, 
           string indent = "  ", 
           string cum_indent = "", 
           string trailer = "\n")
  (A appender, ref T t) if(!isPointer!T) {
  const string new_indent = cum_indent ~ indent;
  static if (is(T == struct) || is(T == class)) {
    static if(is(T == class)) {
      if(!t) {
        appender.put(text("null", trailer));
        return;
      }
    } 

    static if(__traits(compiles, t.pprint(indent, cum_indent, trailer))) {
      appender.put(t.pprint(indent, cum_indent, trailer));
      return;
    } else static if(isIterable!T) {
      appender.put("[\n");
      int index = 0;

      foreach(ref item; t) {
        appender.put(new_indent);
        appender.put(text("[", index++, "]->"));
        print!(typeof(item), A, indent, new_indent)(appender, item);
      }
      appender.put(text(indent, "]", trailer));
      return;
    } else {
      appender.put("{\n");
      foreach (i, field; t.tupleof) {
        auto fieldName = T.tupleof[i].stringof;
        appender.put(text(new_indent, fieldName, " = "));
        print!(typeof(field), A, indent, new_indent)(appender, field);
      }
      appender.put(text(cum_indent, "}", trailer));
      return;
    }
  } else static if(is(T == string)) {
    appender.put(text('"', t,"\"", trailer));
  } else static if(isArray!(T)) {
    appender.put("[\n");
    int index = 0;
    foreach(item; t) {
      appender.put(new_indent);
      appender.put(text("[", index++, "]->"));
      print!(typeof(item), A, indent, new_indent)(appender, item);
    }
    appender.put(text(indent, "]", trailer));
    return;
  } else static if(isAssociativeArray!(T)) {
    appender.put("{\n");
    foreach(k,v; t) {
      appender.put(text(new_indent, '('));
      print!(typeof(k), A, indent, new_indent, "")(appender, k);
      appender.put(text(" => \n", new_indent~indent));
      print!(typeof(v), A, indent, new_indent, "")(appender, v);
      appender.put(text("),", trailer));
    }
    appender.put(text(indent, "}", trailer));
    return;
  } else {
    appender.put(text(t, trailer));
    return;
  }
}

/// ditto
private void print(T, A,
           string indent = "  ", 
           string cum_indent = "", 
           string trailer = "\n")
  (A appender, ref T t) if(isPointer!T) {
  static if(isFunctionPointer!T) {
    appender.put(text(typeid(T), trailer));
  } else {
    static if(is(T == void*)) {
      appender.put(text("void*(", t, ")", trailer));
    } else {
      if(!t) {
        appender.put(text("null", trailer));
      } else {
        print!(PointerTarget!T,A,indent,cum_indent,trailer)(appender, *t);
      }
    }
  }
 }

/**
   Pretty print $(D item) to a string.

   Params:
   T = Type of item to pretty print
   indent = String for indentation at each level
   item   = Item to print

   Returns: A string with contents of $(D item)
 */
string pp(T, string indent = " ")(ref T item) {
  auto appender = appender!string();
  print!(T, typeof(appender), indent) (appender, item);
  return appender.data;
}

// end <dmodule pp public_section>


unittest { 
  class Outer { 
    alias int[] IntArray;
    alias int[string] AssocArray;
    enum DarkColor { 
      Black,
      Brown,
      Maroon
    }

    static struct NestedStaticStruct { 
      string str = "str";
      DarkColor darkColor = DarkColor.Maroon;
    }

    struct NestedStruct { 
      string str = "str";
      DarkColor darkColor = DarkColor.Black;
      static DarkColor staticDarkColor = DarkColor.Brown;
    }

    static class NestedStaticClass { 
      int dogMonthsFactor = 7*12;
    }

    class NestedClass { 
      static class DeeperNesting { 
        int nestingIndex = 25*3;
        string nestingText = "sweet";
        private {
          class CrazyNesting { 
          }
        }
      }

      int dogYearsFactor = 7;
      string catLives = "seven";
    }

    IntArray intArray = [1,2,3];
    AssocArray assocArray;
    NestedStruct nestedStruct;
    NestedStaticStruct nestedStaticStruct;
    NestedClass nestedClass;
    NestedStaticClass nestedStaticClass;
    NestedClass nestedNullClass;
  }

// custom <dmodule pp unittest>

  import std.stdio;
  auto o = new Outer;
  o.nestedClass = o.new Outer.NestedClass();
  o.nestedStaticClass = new Outer.NestedStaticClass();
  o.assocArray = ["son":2, "dad":34, "mom":32];
  const string expected = `{
 (Outer).intArray = [
  [0]->1
  [1]->2
  [2]->3
 ]
 (Outer).assocArray = {
  ("mom" => 
   32),
  ("son" => 
   2),
  ("dad" => 
   34),
 }
 (Outer).nestedStruct = {
  (NestedStruct).str = "str"
  (NestedStruct).darkColor = Black
 }
 (Outer).nestedStaticStruct = {
  (NestedStaticStruct).str = "str"
  (NestedStaticStruct).darkColor = Maroon
 }
 (Outer).nestedClass = {
  (NestedClass).dogYearsFactor = 7
  (NestedClass).catLives = "seven"
 }
 (Outer).nestedStaticClass = {
  (NestedStaticClass).dogMonthsFactor = 84
 }
 (Outer).nestedNullClass = null
}
`;
  assert(pp(o) == expected);

// end <dmodule pp unittest>
}

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
