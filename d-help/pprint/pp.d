/**
   Functions for pretty printing and table printing data
*/

module pprint.pp;

public import opmix.traits;
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.format;
import std.regex;
import std.stdio;
import std.string;
import std.traits;

/**
   Indicates no header should be displayed
*/
const(string[]) NoHeader;

/**
   Indicates the header should be the names of the fields involved
*/
const(string[]) DefaultHeader;

/**
   For table layout printing, which struct fields to use as columns
*/
enum FieldInclusionType { 
  /**
     Include only fields that are accessible
  */
  Accessible,
  /**
     Include inaccessible
  */
  Inaccessible
}


// custom <dmodule pp public_section>

/** Returns the array of cells for this record
 */
private void getCells(T)(ref const(T) record, ref string[] cells) {
  static if(is(T == struct) || is(T == class)) {
    foreach (i, field; record.tupleof) {
      getCells(field, cells);
    }
  } else static if(isIterable!T && !isSomeString!T) {
    foreach(ref cell; record) {
      getCells(cell, cells);
    }
  } else static if(isPointer!T) {
      getCells(*record, cells);
  } else static if(isFloatingPoint!T) {
    cells ~= pp(record);
  } else {
    cells ~= to!string(record);
  }
}

/** Type tuple field names include (Typename).fieldName
 *  This returns the stripped out fieldName
 */
string stripType(string type) {
  static auto r = regex(r"^(\(\w+\)\.)");
  return replace(type, r, "");
}

/** Returns the list field names as the header
 */
void getHeader(T)(ref string[] header, string owner = "") {
  static if(is(T == struct) || is(T == class)) {
    foreach (i, field; typeof(T.tupleof)) {
      auto fieldName = stripType(T.tupleof[i].stringof);
      size_t priorLength = header.length;
      getHeader!(field)(header, owner.length? owner~'.'~fieldName : fieldName);
    }
  } else static if(isIterable!T && !isSomeString!T) {

  } else static if(isPointer!T) {
      getHeader!(PointerTarget!T)(header, owner);
  } else {
    header ~= owner;
  }
}

void putRow(Appender) (Appender appender, string[] row, 
                       size_t[] fieldMaxSizes) {
  appender.put('|');
  foreach(i, cell; row) {
    formattedWrite(appender, "%"~to!string(fieldMaxSizes[i]+1)~"s", cell);
    appender.put('|');
  }
  appender.put('\n');
}

/** Print an iterable of T as a table - the kind you might see output from a
 *  database session. Pass NoHeader to exclude a header, DefaultHeader to use
 *  the field names of type T or your own header.
 */
void printTable(A, T)
  (A appender, ref T items, 
   ref const(string[]) header = DefaultHeader,
   FieldInclusionType inclusionType = FieldInclusionType.Accessible) 
  if(isIterable!T) {

    static if(isAssociativeArray!T) {
      static struct KV {
        KeyType!T key;
        ValueType!T value;
      }
      KV[] flattened;
      flattened.reserve(items.length);
      foreach(k, ref v; items) {
        flattened ~= KV(k,v);
      }
      printTable(appender, flattened, header);
    } else {

      bool excludeHeader = (&header is &NoHeader);
      bool useDefaultHeader = (&header is &DefaultHeader);
      bool includeAllFields = inclusionType == FieldInclusionType.Inaccessible;

      string[][] table;
      size_t[] fieldMaxSizes;

      if(!excludeHeader) {
        if(useDefaultHeader) {
          string[] defaultHeader;
          getHeader!(ForeachType!T)(defaultHeader);
          table ~= defaultHeader;
        } else {
          table ~= header.dup;
        }
        fieldMaxSizes.length = table[0].length;
        foreach(i, headerName; table[0]) {
          fieldMaxSizes[i] = headerName.length;
        }
      }

      foreach(item; items) {
        string[] cells;
        getCells(item, cells);

        if(0 == fieldMaxSizes.length) {
          fieldMaxSizes.length = cells.length;
        }

        foreach(i, cell; cells) {
          fieldMaxSizes[i] = max(fieldMaxSizes[i], cell.length);
        }
        table ~= cells;
      }

      if(excludeHeader) {
        foreach(row; table) {
          putRow(appender, row, fieldMaxSizes);
        }
      } else {
        putRow(appender, table[0], fieldMaxSizes);

        appender.put('|');
        foreach(i, cell; table[0]) {
          foreach(j; 0 .. (fieldMaxSizes[i]+1)) {
            appender.put('-');
          }
          appender.put('|');
        }
        appender.put('\n');

        foreach(row; table[1..$]) {
          putRow(appender, row, fieldMaxSizes);
        }
      }
    }
  }

/** table print the items using default header */
string tp(T)(T items,    
             ref const(string[]) header = DefaultHeader) {
  auto appender = appender!string();
  printTable(appender, items, header);
  return appender.data;
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
  (A appender, ref const(T) t) if(!isPointer!T) {
  const string new_indent = cum_indent ~ indent;
  static if(is(Unqual!T == Date)) {
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
      foreach (i, ref field; t.tupleof) {
        auto fieldName = Unqual!T.tupleof[i].stringof;
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
    appender.put(text('"', t,"\""));
  } else static if(isArray!(T)) {
    appender.put("[");
    static if(!isSomeChar!(ArrayElementType!T)) {
      appender.put(trailer);
    }
    int index = 0;
    foreach(ref item; t) {
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
    foreach(k, ref v; cast(DeepUnqual!(typeof(t)))t) {
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
  (A appender, ref const(T) t) if(isPointer!T) {
  static if(isFunctionPointer!T) {
    appender.put(text(typeid(T), trailer));
  } else {
    static if(is(T == void*) || 
              is(T == immutable(void*)) || 
              is(T == const(void*))) {
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

string pp(T, string indent = " ", string cum_indent = "")(ref const(T) item) {
  auto appender = appender!string();
  print!(T, typeof(appender), indent, cum_indent) (appender, item);
  return appender.data;
  }

/// ditto
string pp(T, string indent = " ", string cum_indent = "")(const(T) item) {
  auto appender = appender!string();
  print!(T, typeof(appender), indent, cum_indent) (appender, item);
  return appender.data;
}

string moneyFormat(T)(T d) if(isFloatingPoint!T) {
  auto appender = appender!string();
  formattedWrite(appender, "%.2f", d);
  return appender.data;
}

// end <dmodule pp public_section>


static if(1) unittest { 
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
  ///////////////////////////////////////////////////////////////////////////
  // Pretty printing
  ///////////////////////////////////////////////////////////////////////////
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

  ///////////////////////////////////////////////////////////////////////////
  // Table printing
  ///////////////////////////////////////////////////////////////////////////
  struct A {
    int x;
    string y;
  }

  struct B {
    A a;
    string name;
    int age;
    double fitzerGuage;
  }

  auto b = [
            B(A(1,"foo"), "doggie", 32, 12.24321),
            B(A(1,"goo"), "maggie", 31, 1200.24321),
            B(A(1,"doo"), "doogie", 34, 12000.24321),
            B(A(1,"boo"), "boogie", 42, 120000000.24321),
            ];

  auto appender = appender!string();
  appender.put("Using default header\n");
  appender.put(tp(b));
  appender.put("\nUsing no header\n");
  printTable(appender, b, NoHeader);
  appender.put("\nUsing custom header\n");

  string[] header = [ "A count", "A label", 
                      "[oa]ggieness", "goodness", "scale"  ];
  printTable(appender, b, header);

  assert(appender.data == 
"Using default header
| a.x| a.y|   name| age|  fitzerGuage|
|----|----|-------|----|-------------|
|   1| foo| doggie|  32|      12.2432|
|   1| goo| maggie|  31|      1200.24|
|   1| doo| doogie|  34|     12000.24|
|   1| boo| boogie|  42| 120000000.24|

Using no header
| 1| foo| doggie| 32|      12.2432|
| 1| goo| maggie| 31|      1200.24|
| 1| doo| doogie| 34|     12000.24|
| 1| boo| boogie| 42| 120000000.24|

Using custom header
| A count| A label| [oa]ggieness| goodness|        scale|
|--------|--------|-------------|---------|-------------|
|       1|     foo|       doggie|       32|      12.2432|
|       1|     goo|       maggie|       31|      1200.24|
|       1|     doo|       doogie|       34|     12000.24|
|       1|     boo|       boogie|       42| 120000000.24|
");

  auto map = [
              "key1" : B(A(1,"zoom"), "doggie", 32, 12.24321),
              "key2" : B(A(1,"broom"), "maggie", 31, 1200.24321),
              ];

  assert(tp(map) == 
         "|  key| value.a.x| value.a.y| value.name| value.age| value.fitzerGuage|
|-----|----------|----------|-----------|----------|------------------|
| key1|         1|      zoom|     doggie|        32|           12.2432|
| key2|         1|     broom|     maggie|        31|           1200.24|
");

// end <dmodule pp unittest>
}

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
