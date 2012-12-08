/**
   Functions for pretty printing data
*/

module pprint.pp;

import std.array;
import std.conv;
import std.stdio;
import std.traits;
import std.string;
import std.datetime;
import std.format;


// custom <dmodule pp public_section>

template ArrayElementType(T : U[], U) {
  alias U ArrayElementType;
}

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

  static if(is(T == Date)) {
    appender.put(to!string(t));
  } else static if (is(T == struct) || is(T == class)) {
    static if(is(T == class)) {
      if(!t) {
        appender.put(text("null"));
        return;
      }
    } 

    static if(__traits(compiles, t.pprint(indent, cum_indent, trailer))) {
      appender.put(t.pprint(indent, cum_indent, trailer));
      return;
    } else static if(isIterable!T) {
      appender.put(text("[", trailer));
      int index = 0;

      foreach(ref item; t) {
        if(index) appender.put(trailer);
        appender.put(text(new_indent, "[", index++, "]->"));
        print!(typeof(item), A, indent, new_indent, trailer)(appender, item);
      }
      appender.put(text(trailer, cum_indent, "]"));
      return;
    } else {
      appender.put(text("{"));
      foreach (i, field; t.tupleof) {
        auto fieldName = T.tupleof[i].stringof;
        appender.put(text(trailer, new_indent, fieldName, " = "));
        static if(isPointer!(typeof(T.tupleof[i])) &&
                  (is(Unqual!(PointerTarget!(typeof(T.tupleof[i]))) ==
                      Unqual!T))) {
          appender.put(text(indent, field, trailer));
        } else {
          print!(typeof(field), A, indent, new_indent, trailer)(appender, field);
        }
      }
      appender.put(text(trailer, cum_indent, "}"));
      return;
    }
  } else static if(isSomeString!T && !isStaticArray!T) {
      //    appender.put(text('"', t,"\"", trailer));
    appender.put(text('"', t,"\""));
  } else static if(isArray!(T)) {
    appender.put("[");
    static if(!isSomeChar!(ArrayElementType!T)) {
      appender.put(trailer);
    }
    int index = 0;
    foreach(item; t) {
      if(index) appender.put(trailer);
      appender.put(text(new_indent, "[", index++, "]->"));
      // Here be sure not to output '0' character directly
      static if(isSomeChar!(typeof(item))) {
        if(item) { 
          appender.put(item);
        } else {
          appender.put("<null>");
        }
      } else {
        print!(typeof(item), A, indent, new_indent, trailer)(appender, item);
      }
    }
    appender.put(text(trailer, cum_indent, "]"));
    return;
  } else static if(isAssociativeArray!(T)) {
    appender.put(text("{"));
    size_t index;
    foreach(k,v; t) {
      appender.put(text(trailer, new_indent, '(', "K("));
      print!(typeof(k), A, indent, new_indent, trailer)(appender, k);
      appender.data.chomp();
      appender.put(text(")[", index++, "]"));
      appender.put(text(" => ", trailer, new_indent~indent, "V("));
      print!(typeof(v), A, indent, new_indent~indent, trailer)(appender, v);
      appender.data.chomp();
      appender.put(")");
      appender.put(text("),"));
    }
    appender.put(text(trailer, cum_indent, "}"));
    return;
  } else static if (isFloatingPoint!T) {
      if(t > 1000) {
        formattedWrite(appender, "%.2f", t);
      } else {
        appender.put(text(t));
      }
  } else {
    appender.put(text(t));
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
string pp(T, string indent = " ", string cum_indent = "")(ref T item) {
  auto appender = appender!string();
  print!(T, typeof(appender), indent, cum_indent) (appender, item);
  return appender.data;
}

/// ditto
string pp(T, string indent = " ", string cum_indent = "")(T item) {
  auto appender = appender!string();
  print!(T, typeof(appender), indent, cum_indent) (appender, item);
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
  (K("mom")[0] => 
   V(32)),
  (K("son")[1] => 
   V(2)),
  (K("dad")[2] => 
   V(34)),
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
}`;
  assert(pp(o) == expected);

// end <dmodule pp unittest>
}

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
