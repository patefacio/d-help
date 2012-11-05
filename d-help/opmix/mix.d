/**
   Provide some standard mixins. For background on the point of this see an
   interesting thread:
   http://forum.dlang.org/post/iphhuttpkogmfwpuvfla@forum.dlang.org
   
   Overcomes this problem:
   
   	writeln(  [1: 2]  ==   [1: 2] );  // true
   	writeln(S([1: 2]) == S([1: 2]));  // false
   
   by allowing:
   
   	writeln(typesDeepEqual(S([1: 2]), S([1: 2]))); // true
   
   and allowing:
   
   struct S {
     mixin(OpEquals);
     int[int] _m;
   }
   
   to give:
   
   	writeln(S([1: 2]) == S([1: 2]));  // now true false
   
   Provides other mixins like: OpCmp, Dup, Deep, PostBlit, ToHash, HashSupport
*/

module opmix.mix;

import std.algorithm;
import std.math;
import std.stdio;
import std.string;
import std.traits;

/**
   Set this to true to see what is going on at compile time
*/
const bool LogCompile = false;

/**
   Set this to true to see what is going on at runtime - potentially expensive!
*/
const bool LogRunTime = false;

const string OpEquals = `
bool opEquals(const ref typeof(this) other) const {
  mixin(LogInfo("opEquals by ref ", "typeof(this)", "this"));
  return typesDeepEqual(this, other);
}

bool opEquals(const typeof(this) other) const {
  mixin(LogInfo("opEquals by val ", "typeof(this)", "this"));
  return typesDeepEqual(this, other);
}
`
;

/**
   Mixin to provide reasonable opCmp. It deeply compares the fields of the struct
   and assumes member structs have suitable opCmp. Use this, for example, to
   enable storing instances in a RedBlackTree.
*/
const string OpCmp = `
int opCmp(const ref typeof(this) other) const {
  return typesDeepCmp(this, other);
}

int opCmp(const typeof(this) other) const {
  return typesDeepCmp(this, other);
}
`
;

/**
   Mixin to provide a reasonable dup. dup is not really part of the language but
   rather a convention used to copy items that have aliasing/sharing. For
   example, dynamic arrays, associative, BitArray, HTTP have dup defined since a
   basic assignment of them introduces sharing. So if you want your class to have
   aliasing but still want an out mixin(Dup) and don't bother with
   mixin(PostBlit).
*/
const string Dup = `

  @property auto idup() const {
    alias typeof(this) ThisType;
    return cast(immutable(ThisType)) this.dup;
  }

  @property auto dup() const {
    alias Unqual!(typeof(this)) UnqualThisType;

    UnqualThisType result;    

    foreach (i, field ; typeof(UnqualThisType.tupleof)) {
      alias typeof(result.tupleof[i]) FieldType;

      enum fieldHasDup = HasDup!FieldType;
      enum fieldIsDynamicArray = isDynamicArray!(FieldType);
      enum isPointer = isPointer!(FieldType);

      static if(isPointer) {
        alias PointerTarget!(FieldType) TargetType;
        FieldType fieldPtr = cast(FieldType)this.tupleof[i];
        if(fieldPtr) {
          static if(__traits(compiles, (result.tupleof[i] = new TargetType))) {
             result.tupleof[i] = new TargetType;
             *result.tupleof[i] = *fieldPtr;
          } else {
             pragma(msg, "Unable to heap allocate '", 
                    typeof(result.tupleof[i]), " ", typeof(this).tupleof[i].stringof, 
                    "', using pointer copy");
             result.tupleof[i] = fieldPtr;
          }
        }
      } else static if(fieldIsDynamicArray || fieldHasDup) {
        result.tupleof[i] = cast(typeof(result.tupleof[i])) this.tupleof[i].dup;
        static if (fieldIsDynamicArray) {
          assert((result.tupleof[i] is null) || (result.tupleof[i].ptr != this.tupleof[i].ptr));
        }
      } else {
        result.tupleof[i] = this.tupleof[i];
      }
    }

    return result;
  }
`;

/**
   Mixin to provide both a post blit and opEquals which usually go together.
*/
const string Deep = `
  mixin(PostBlit);
  mixin(OpEquals);
`;

/**
   Mixin to provide a this(this). This is very similar to dup in that it calls
   dup on all dupable fields of the struct. Decide up front if you want deep
   semantics (i.e. assignment will make deep copies of all members) on your
   struct. If you do, use this to get that. This is only useful if one or more of
   your fields require deep copy (like associative arrays, arrays, other classes
   with dup). If you are ok with shallow semantics, forego this and consider
   using mixin(Dup) to allow for deep copy. If you decide to go the PostBlit
   route, you probably need an opEquals with deep comparison. So consider
   mixin(DeepSemantics) wich includes mixin(PostBlit) and mixin(OpEquals).
*/
const string PostBlit = `

  this(this) {
    alias typeof(this) T;
    foreach (i, field ; typeof(T.tupleof)) {
      alias typeof(T.tupleof[i]) FieldType;

      enum fieldHasDup = HasDup!FieldType;
      enum fieldIsDynamicArray = isDynamicArray!(FieldType);
      enum fieldIsAssociativeArray = isAssociativeArray!(FieldType);
      enum isPointer = isPointer!(FieldType);

      static if(isPointer) {
        alias PointerTarget!(FieldType) TargetType;
        FieldType fieldPtr = cast(FieldType)this.tupleof[i];
        if(fieldPtr) {
          static if(__traits(compiles, (this.tupleof[i] = new TargetType))) {
             this.tupleof[i] = new TargetType;
             *this.tupleof[i] = *fieldPtr;
          } else {
             pragma(msg, "Unable to heap allocate '", 
                    typeof(this.tupleof[i]), " ", typeof(this).tupleof[i].stringof, 
                    "', using pointer copy");
             this.tupleof[i] = fieldPtr;
          }
        }
      } else static if(fieldIsDynamicArray || fieldIsAssociativeArray || fieldHasDup) {
        this.tupleof[i] = cast(typeof(this.tupleof[i])) this.tupleof[i].dup;
      }
    }
  }
`;

/**
   Mixin to provide toHash for a struc that incorporates some aspect of all
   fields to the function.
*/
const string ToHash = `
  /**
    Hashing function hitting all data - mileage may vary.
    TODO: Make this and fieldsToHash pure when foreach iteration permits
   */
  hash_t toHash() const /* pure */ nothrow {
    return fieldsToHash!(typeof(this))(this);
  }
`;

/**
   Mixin to provide hashing functionality on a struct. For example, to make your
   struct usable as a key in an associative array you need to provide suitable
   and consistent toHash, opCmp, and opEquals. This mixin pulls in all three.
   
   According to the language spec: 
   
   'The implementation may use either opEquals or opCmp or both. Care should be
   taken so that the results of opEquals and opCmp are consistent with each other
   when the class objects are the same or not.'
   
   It is not clear whether that means you can leave opCmp out and it is capable
   of using opEquals alone... I had trouble there, so both are pulled in.
   
   In terms of performance, the point of the hash function is to get a good
   distribution. This implementation may be very expensive to compute compared to
   other custom hashes and it may not provide a good distribution. But you should
   be able to store HashSupport structs in a hash.
*/
const string HashSupport = `
  mixin(OpEquals);
  mixin(OpCmp);
  mixin(ToHash);
`;



/** 
  For debugging, logs a compile time message at various points. If mixing in
  OpEquals or hashing and there are compile errors, maybe something in the
  struct is missing. The compile time logs help determine at what stage
  compilation goes off the rails.  To enable set LogCompile to true.
*/
string LogInfo(string tag, string T, string instance) { 
  return `
  static if(LogCompile) {
    pragma(msg, "CT: `~tag~`", `~T~`);
  }
  static if(LogRunTime) {
    writeln("RT: `~tag~`", `~instance~`);
  }`;
}

/** Compare for equality all fields in a class
    Original courtesy of Tobias Pankrath
    Updated to use tupleof instead of getMember and short circuits
    Supports associative and dynamic arrays
    Treats default float.init as equal
 */
bool typesDeepEqual(T,F)(auto ref T lhs, auto ref F rhs) if(is(Unqual!T == Unqual!F)) {
    mixin(LogInfo("typesDeepEqual by ref ", "T", "lhs"));
    bool result = true;

    if(lhs is rhs) { return true; }

    static if(isFloatingPoint!(T)) {
      mixin(LogInfo("...typesDeepEqual floating ", "T", "lhs"));
      if(!isnan(lhs) || !isnan(rhs)) {
          result &= lhs == rhs;  
      }
      // both nan, assume equal - maybe should make configurable
    } else static if(isPointer!(T)) {
      mixin(LogInfo("...typesDeepEqual pointer ", "T", "lhs"));
      if(lhs && rhs) {
        result &= typesDeepEqual(*lhs, *rhs);
      } else {
        result = !(lhs || rhs);
      }
    } else static if(isAssociativeArray!(T)) {
      mixin(LogInfo("...typesDeepEqual assoc array ", "T", "lhs"));

      ///// TODO: Remove const casts on length and keys when no longer
      ///// necessary. Note: important to cast away const on both key and
      ///// value.
      alias KeyType!(T) AAKeyType;
      alias ValueType!(T) AAValueType;
      alias Unqual!(AAValueType)[Unqual!(AAKeyType)] NoConstAssocArr;
      if((cast(NoConstAssocArr)lhs).length != (cast(NoConstAssocArr)rhs).length) return false;
      auto lhsKeys = (cast(NoConstAssocArr)lhs).keys.dup;
      auto rhsKeys = (cast(NoConstAssocArr)rhs).keys.dup;

      lhsKeys.sort;
      rhsKeys.sort;
      for(size_t i=0; i<lhsKeys.length; ++i) {
          if(!typesDeepEqual(lhsKeys[i], rhsKeys[i])) return false;
          const(AAValueType)* lvalue = lhsKeys[i] in lhs;
          const(AAValueType)* rvalue = rhsKeys[i] in rhs;
          if(!((lvalue && rvalue)? typesDeepEqual(*lvalue, *rvalue) : lvalue == rvalue)) return false;
      }
    } else static if(isDynamicArray!(T)) {
      mixin(LogInfo("...typesDeepEqual dynamic array ", "T", "lhs"));
      auto llen = lhs.length, rlen = rhs.length;
      auto end = min(llen, rlen);
      for(size_t i=0; i<end; ++i) {
        if(!typesDeepEqual(lhs[i], rhs[i])) return false;
      }
      result = llen == rlen;
    } else static if(is(T == struct)) {
      mixin(LogInfo("...typesDeepEqual struct ", "T", "lhs"));
      foreach (i, ignore ; typeof(T.tupleof)) {
        mixin(LogInfo("struct field <"~lhs.tupleof[i].stringof~">", "T.tupleof[i]", "lhs.tupleof[i]"));
        static if(T.tupleof[i].stringof.endsWith(".this")) {
          // Skip if nested class
        } else {
          result &= typesDeepEqual(lhs.tupleof[i], rhs.tupleof[i]);
        }
        if(!result) return false;
      }
    } else {
      mixin(LogInfo("...typesDeepEqual catch-all ", "T", "lhs"));
      result = lhs == rhs;
    }
    return result;
  }

/** Compare all fields for suitable opCmp.
    Order will be that returned by T.tupleof
 */
int typesDeepCmp(T,F)(auto ref T lhs, auto ref F rhs) if(is(Unqual!T == Unqual!F)) {

  static if(isFloatingPoint!(T)) {
    if(isnan(lhs) && isnan(rhs)) { return 0; }
    return (lhs<rhs)? -1 : (lhs>rhs)? 1 : 0;
  } else static if(is(T == struct)) {
      foreach (i, ignore ; typeof(T.tupleof)) {
        static if(T.tupleof[i].stringof.endsWith(".this")) {
          // Skip if nested class
        }
        int result = typesDeepCmp(lhs.tupleof[i], rhs.tupleof[i]);
        if(result) return result;
      }
      return 0;
  } else static if(isPointer!(T)) {
      int result;
      if(lhs && rhs) {
        result = typesDeepCmp(*lhs, *rhs);
      } else {
        result = rhs? -1 : lhs? 1 : 0;
      }
      return result;
  } else static if(isAssociativeArray!(T)) {

    ///// TODO: Remove const casts on keys
    // Compare keys in order
    alias Unqual!(ValueType!T)[Unqual!(KeyType!T)] NoConstAssocArr;
    if((cast(NoConstAssocArr)lhs).length != (cast(NoConstAssocArr)rhs).length) return false;
    auto lhsKeys = (cast(NoConstAssocArr)lhs).keys.dup;
    auto rhsKeys = (cast(NoConstAssocArr)rhs).keys.dup;

    lhsKeys.sort;
    rhsKeys.sort;

    auto keysCmp = cmp(lhsKeys, rhsKeys);
    if(keysCmp) { return keysCmp; }

    foreach(ref key; lhsKeys) {
      auto lhsVal = key in lhs;
      auto rhsVal = key in rhs;

      if(lhsVal && rhsVal) { 
        auto result = typesDeepCmp(*lhsVal, *rhsVal);
        if(result) return result;
      } else if(rhsVal) { 
        return -1;
      } else { 
        return 1;
      }
    }

    return 0;
  } else {
    return (lhs < rhs)? -1 : (lhs > rhs)? 1 : 0;
  }
}

/**

  Computes a hash taking into account all fields. A good question in a long
  thread was posed here
  http://forum.dlang.org/post/jiweknaxeaeepjlvhrlf@forum.dlang.org

  This uses the same ideas and provides function to wrap as mixin.

 */
hash_t fieldsToHash(T)(const ref T t) nothrow { 
  const int prime = 23;
  hash_t result = 17;
  static if(isPointer!T) {
    mixin(LogInfo("Hashing ptr ", "T", "t"));
    alias PointerTarget!(T) TargetType;
    if(t) {
      result = result*prime + fieldsToHash(*t);
    }
  } else static if(isAssociativeArray!T) {
    try {
      foreach(key, value; t) {
        mixin(LogInfo("Hashing assoc array ", "T", "t"));
        result = result*prime + fieldsToHash(key);
        result = result*prime + fieldsToHash(value);
      }
    } catch(Exception) {
      assert(0);
    }
  } else static if(isArray!T) {
    mixin(LogInfo("Hashing array ", "T", "t"));
    size_t end = t.length;
    for(size_t i=0; i<end; ++i) {
      result = result*prime + fieldsToHash(t[i]);
    }
  } else static if(isSomeString!(T)) {
    mixin(LogInfo("Hashing string ", "T", "t"));
    result = result*prime + typeid(T).getHash(&t);
  } else static if (isIntegral!(T) || isSomeChar!(T) || 
                    isBoolean!(T) || is(T==enum)) {
    mixin(LogInfo("Hashing integral, char, bool, enum ", 
                  "T", "t"));
    result = result*prime + t;
  } else static if (isFloatingPoint!(T)) {
    mixin(LogInfo("Hashing floating point ", "T", "t"));
    byte[T.sizeof] *buff = cast(byte[T.sizeof]*)&t;
    for(size_t i=0; i<T.sizeof; ++i) {
      result = result*prime + (*buff)[i];
    }
  } else static if (is(T == struct) || is(T == class)) {
    mixin(LogInfo("Hashing struct ", "T", "t"));
    static if(is(T == class)) {
      if(!t) {
        return result;
      }
    } 
    foreach (i, ignore ; typeof(T.tupleof)) {
      static if(T.tupleof[i].stringof.endsWith(".this")) {
      } else {
        result = result*prime + fieldsToHash(t.tupleof[i]);
      }
    }
  } else {
    assert(false);
  }

  return result;
}

template HasDup(T) { 
  enum HasDup = __traits(hasMember, T, "dup"); 
}

template HasToHash(T) { 
  enum HasToHash = __traits(hasMember, T, "toHash"); 
}

template IsImmutable(T) { 
  static if(is(T U == immutable U)) {
    enum IsImmutable = true;
  } else {
    enum IsImmutable = false;
  }
}



// custom <dmodule mix public_section>
// end <dmodule mix public_section>


unittest { 
  /**
     Usage of basic associative array in struct.
  */
  struct WrappedHash { 
    mixin(HashSupport);
    mixin(Dup);
    private {
      int[string] _m;
      string _s = "s";
    }
  }

  /**
     Usage of post blit for struct.

     By including Deep, PostBlit is pulled in and this(this) is suitably defined to
     dup all that are dupable. Additionally OpEquals is pulled so instances can be
     deep compared.
  */
  struct PostBlitExample { 
    mixin(Deep);
    private {
      int[string] _m;
      char[] _c;
      string _s = "s";
    }
  }

  /**
     Struct with most basic types (missing [i|c][float|double|real])
  */
  struct BasicTypes { 
    mixin(HashSupport);
    mixin(Dup);
    private {
      bool _bool;
      byte _byte;
      ubyte _ubyte;
      short _short;
      ushort _ushort;
      int _int;
      uint _uint;
      long _long;
      ulong _ulong;
      float _float;
      double _double;
      real _real;
      char _char;
      wchar _wchar;
      dchar _dchar;
      string _string;
    }
  }

  /**
     Top level class with nested classes for testing HashSupport(OpCmp and OpEquals) and Dup.
  */
  struct A { 
    alias string[string] SSAArr;
    alias B[B] BBAArr;
    alias int* IntPtr;
    alias B* BPtr;
    mixin(HashSupport);
    mixin(Dup);
    struct B { 
      mixin(HashSupport);
      mixin(Dup);
      private {
        char[] _bw;
        string _bx = "foo";
        int _by = 3;
        string _bz = "zoo";
      }
    }

    private {
      char[] _w;
      string _x = "foo";
      int _y = 3;
      string _z = "zoo";
      B _b;
      SSAArr _map;
      BBAArr _bMap;
      BPtr _bPtr;
      IntPtr _intPtr;
    }
  }

// custom <dmodule mix unittest>

  import std.stdio;

  // Default comparison of associative arrays does not work, should not do
  // this
  assert((["fo".idup:2] < ["fo".idup:3]) == (["fo".idup:3] < ["fo".idup:2]));

  auto z1 = ["fo".idup:2], z2 = ["fo".idup:2];
  //assert(typesDeepEqual(["fo".idup:2], ["fo".idup:2]));
  assert(typesDeepEqual(z1,z2));

  {
    // Expensive for hashes: opCmp compares keys/values ordered - so wrapping in
    // struct and adding HashSupport brings in OpCmp, OpEquals and ToHash
    assert(WrappedHash(["fo".idup:2]) == WrappedHash(["fo".idup:2]));
    assert(WrappedHash(["fo".idup:2]) < WrappedHash(["fo".idup:3]));
    assert(WrappedHash(["fo".idup:3]) > WrappedHash(["fo".idup:2]));
    assert(!(WrappedHash(["fo".idup:3]) < WrappedHash(["fo".idup:3])));
    assert(!(WrappedHash(["fo".idup:3]) > WrappedHash(["fo".idup:3])));
    assert(WrappedHash(["fo".idup:3]) !in [ WrappedHash(["fo".idup:2]) : 3 ]);
    assert(WrappedHash(["fo".idup:3]) in [ WrappedHash(["fo".idup:3]) : 3 ]);
    auto wh = WrappedHash(["test".idup:4]);
    assert((wh == wh.dup) && (wh.toHash() && (wh.toHash() == wh.dup.toHash())));
  }

  {
    PostBlitExample ex1;
    ex1._m["foo".idup] = 42;
    ex1._s = "this is a test".idup;
    PostBlitExample ex2 = ex1;
    // they are deep equal
    assert(ex1 == ex2);
    // they are not sharing
    assert(ex1._s.ptr != ex2._s.ptr);
    ex1._m["foo"]++;
    assert(ex1._m != ex2._m);
  }

  void equalHashSanity(T)(const ref T lhs, const ref T rhs) {
    assert(lhs == rhs);    

    assert(!(lhs<rhs));
    assert(!(rhs>lhs));
    auto h1 = lhs.toHash();
    assert(h1);
    assert(h1 == lhs.dup.toHash());
    assert(h1 == rhs.toHash());
  }

  BasicTypes bt1, bt2;
  equalHashSanity(bt1, bt2);
  foreach (i, ignore ; typeof(BasicTypes.tupleof)) {
    static if(isNumeric!(typeof(BasicTypes.tupleof[i]))) {
      static if(isFloatingPoint!(typeof(BasicTypes.tupleof[i]))) {
        bt1.tupleof[i] = bt2.tupleof[i] = 3;
      }
      bt2.tupleof[i]++;
      assert(bt1<bt2);
      assert(bt2>bt1);
      bt2.tupleof[i]--;
      equalHashSanity(bt1, bt2);
    } else static if(isSomeChar!(typeof(BasicTypes.tupleof[i]))) {
        bt1.tupleof[i] = 'a';
        bt2.tupleof[i] = 'b';
        assert(bt1<bt2);
        assert(bt2>bt1);
        bt2.tupleof[i] = 'a';
        equalHashSanity(bt1, bt2);
    } else static if(isBoolean!(typeof(BasicTypes.tupleof[i]))) {
        bt2.tupleof[i] = true;
        assert(bt1<bt2);
        assert(bt2>bt1);
        bt1.tupleof[i] = true;
        equalHashSanity(bt1, bt2);
    } else static if(isSomeString!(typeof(BasicTypes.tupleof[i]))) {
        bt1.tupleof[i] = "alpha";
        bt2.tupleof[i] = "beta";
        assert(bt1<bt2);
        assert(bt2>bt1);
        bt1.tupleof[i] = "beta";
        equalHashSanity(bt1, bt2);
    } else {
      pragma(msg, "Deal with ", BasicTypes.tupleof[i]);
    }
  }

  // Create s.t. a==b and a!=c
  A a, b, c = { _w : ['a','b'], _x : "goo".idup, _map : [ "grape".idup : "vine".idup ] };
  // Copy same string different address keeping a==b
  b._x = "foo".idup;

  assert(a.toHash() && (a.toHash() == a.dup.toHash()));

  // Similar for const objects
  const(A) ca, cb, cc = { _w : ['a','b'], _x : "goo".idup, _map : [ "grape".idup : "vine".idup ] };

  // without opEquals deep equality compare will fail until 3789 fixed
  equalHashSanity(a, b);
  equalHashSanity(ca, cb);

  assert((a == b) && (a != c) && (ca == cb) && 
         (ca != cc) && (a == ca) && (a != cc));
  assert(!(a < b) && !(b < a) && (a < c) && !(c < a));
  assert(!(a < cb) && !(cb < a) && (a < cc) && !(c < ca));

  // Now patch a and c to b equal
  a._map["grape"] = "vine";
  a._w = ['a','b'];
  c._x = "foo";
  assert(a == c);
  // Clear a to be back like b
  a._map.clear();
  a._w.clear();
  assert(a == b);

  // Change nested B's y and ensure difference picked up and cmp catches it correctly
  a._b._by++;
  assert((a != b) && (b != a));
  assert((b < a) && !(b > a));

  a._b._by--;
  assert(a==b);
  a._bPtr = new A.B;
  assert(a != b);
  // For opCmp - one with vs one without, smaller without
  assert(b < a);
  b._bPtr = new A.B;
  assert(a==b);
  b._bMap[a._b.dup] = a._b.dup;
  assert(a!=b);
  a._bMap[a._b.dup] = a._b.dup;
  assert(a==b);
  a._intPtr = new int;
  *a._intPtr = 42;
  assert(a!=b);
  b._intPtr = new int;
  *b._intPtr = 20+22;
  assert(a==b);

  A dup = a.dup;
  assert(dup == a);
  assert(dup._bPtr != a._bPtr && *dup._bPtr == *a._bPtr);

  // Series of changes on one or the other to ensure picked up by equals
  dup._b._bx = "not foo";
  assert(dup != a);
  dup = a.dup;
  assert(dup == a);
  dup._b._bx = "foo";
  assert(dup == a);

  // Change some of duped and ensure different
  dup._b._bw = [ 'a', 'b', 'c' ];
  assert(dup != a);
  dup._b._bw = a._b._bw;
  assert(dup == a);
  dup._bPtr._bw = [ 'd', 'e', 'f' ];
  assert(dup != a);

  auto idup = a.idup;
  dup = a.dup;
  assert((idup == a) && (idup == dup));
  assert(IsImmutable!(typeof(idup)) && !IsImmutable!(typeof(dup)));
  assert(a.dup.idup == a.idup.dup);

  /// Demonstrate bypassing '==', using typesDeepEqual instead.
  WrappedHash wh1, wh2;
  // unwrapped hashes
  WrappedHash[string] uwh1, uwh2;
  // unwarpped hashes of unwrapped hashes
  WrappedHash[WrappedHash[string]] uwhuwh1, uwhuwh2;
  // As established, here these are equal purely out of luck - because empty
  assert(wh1==wh2);
  assert(uwh1==uwh2);
  assert(uwhuwh1==uwhuwh2);
  uwhuwh1[uwh1.dup] = wh1.dup;
  uwhuwh2[uwh1.dup] = wh2.dup;
  // Now not empty - '==' not deep compare
  assert(uwhuwh1 != uwhuwh2);
  assert(typesDeepEqual(uwhuwh1,uwhuwh2));
  writeln("Done");

// end <dmodule mix unittest>
}

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
