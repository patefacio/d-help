module opmix.d_test.mix;

import dunit;
import opmix.mix;
import std.algorithm;
import std.math;
import std.stdio;
import std.string;
import std.traits;

class HashSupportTest { 
  mixin TestMixin;
  /**
     Usage of basic associative array in struct.  Hash support is
     irrespective of copy semantics.  This class, mixing in Dup and not
     PostBlit has reference semantics.
  */
  static struct WrappedHash { 
    mixin HashSupport;
    mixin Dup;
    

// custom <dstruct wrapped_hash public_section>
// end <dstruct wrapped_hash public_section>

    private {
      int[string] _m;
      string _s = "s";
    }
  }


  void testHashing() {
  
// custom <hash_support_testtest_hashing>

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
    auto wh2 = wh;

// end <hash_support_testtest_hashing>
  }


  void testTypesDeepEqual() {
  
// custom <hash_support_testtest_types_deep_equal>

    auto z1 = ["fo".idup:2], z2 = ["fo".idup:2];
    // typesDeepCmp(auto ref T...) signature required for literals
    assert(typesDeepEqual(["fo".idup:2], ["fo".idup:2]));
    assert(typesDeepEqual(z1,z2));

    /// Demonstrate bypassing '==', using typesDeepEqual instead.
    WrappedHash wh1, wh2;
    // unwrapped hashes
    WrappedHash[string] uwh1, uwh2;
    // unwarpped hashes of unwrapped hashes
    WrappedHash[WrappedHash[string]] uwhuwh1, uwhuwh2;
    // As established, here these are equal purely out of luck - because empty
    assertEquals(wh1,wh2);
    assertEquals(uwh1,uwh2);
    assertEquals(uwhuwh1,uwhuwh2);
    uwhuwh1[uwh1.dup] = wh1.dup;
    uwhuwh2[uwh1.dup] = wh2.dup;
    // The are deep equal when using the global function
    assert(typesDeepEqual(uwhuwh2, uwhuwh1));

    // Since no postblit, they are not equal with '==' 

    // This used to assert just fine, but they have improved hash comparison
    // to actually do deep compare - or rather to use your opEquals on values
    // if you have defined one.
    // assert(uwhuwh1 != uwhuwh2);

// end <hash_support_testtest_types_deep_equal>
  }
}

class HashDeepSemantics { 
  mixin TestMixin;
  /**
     Similar to above, but with deep semantics (mixin PostBlit) causing
     immutable(T)[] to be shallow copied since its safe.
  */
  static struct WrappedHashDeep { 
    mixin HashSupport;
    mixin PostBlit;
    mixin Dup;
    
// custom <dstruct wrapped_hash_deep public_section>
// end <dstruct wrapped_hash_deep public_section>

    private {
      int[string] _m;
      string _s = "s";
      char[] _ca;
    }
  }


  void testHashing() {
  
// custom <hash_deep_semanticstest_hashing>

    auto arr = ["fo":2];
    WrappedHashDeep wh1 = {arr, "somestring"};
    wh1._ca = [ 'a', 'b', 'c'];
    WrappedHashDeep wh2 = wh1;
    // Since _s is immutable(T)[] it is shallow copied
    assert(wh1._s.ptr == wh2._s.ptr);
    // Since _ca is mutable T[] it is deep copied
    assert(wh1._ca.ptr != wh2._ca.ptr);
    // And yet
    assert(wh1==wh2);
    wh1._ca[2] = 'd';
    assert(wh1 > wh2);
    assert(wh2 < wh1);
    wh2._ca[2] = 'd';
    assert(!(wh1 < wh2));
    assert(!(wh2 < wh1));
    assert(wh1 in [ wh2 : 3 ]);
    wh1._ca[2] = 'e';
    assert(wh1 !in [ wh2 : 3 ]);

// end <hash_deep_semanticstest_hashing>
  }
}

class PostBlitDeepSemantics { 
  mixin TestMixin;
  static struct WrappedHash { 
    mixin HashSupport;
    mixin Dup;
    

// custom <dstruct wrapped_hash public_section>
// end <dstruct wrapped_hash public_section>

    private {
      int[string] _m;
      string _s = "s";
    }
  }

  /**
     Usage of post blit for struct.

     By including Deep, PostBlit is pulled in and this(this) is suitably
     defined to dup all that are dupable. Additionally OpEquals is
     pulled so instances can be deep compared.
  */
  static struct PostBlitExample { 
    mixin Deep;
    mixin Dup;
    
// custom <dstruct post_blit_example public_section>
// end <dstruct post_blit_example public_section>

    private {
      int[string] _m;
      char[] _c;
      string _s = "s";
      const(WrappedHash)[] _wh;
    }
  }


  void testDeepSemantics() {
  
// custom <post_blit_deep_semanticstest_deep_semantics>

    PostBlitExample ex1;
    auto arr = ["fo":2];
    ex1._m["foo".idup] = 42;
    ex1._s = "this is a test".idup;
    ex1._c = ['a','b','c'];
    const(WrappedHash) cwh = {arr, "goo"};
    ex1._wh ~= cwh;
    PostBlitExample ex2 = ex1;
    // they are deep equal
    assertEquals(ex1, ex2);
    // they are sharing arrays of immutable, but that is ok
    assertEquals(ex1._s.ptr, ex2._s.ptr);
    // they are not sharing arrays
    assertNotEquals(ex1._c.ptr, ex2._c.ptr);
    ex1._m["foo"]++;
    assertNotEquals(ex1._m, ex2._m);

// end <post_blit_deep_semanticstest_deep_semantics>
  }
}

class BasicTypeCoverage { 
  mixin TestMixin;
  /**
     Struct with most basic types (missing [i|c][float|double|real])
  */
  static struct BasicTypes { 
    mixin HashSupport;
    mixin Dup;
    
// custom <dstruct basic_types public_section>
// end <dstruct basic_types public_section>

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


  void testCoverage() {
  
// custom <basic_type_coveragetest_coverage>

    BasicTypes bt1, bt2;
    equalHashSanity(bt1, bt2);
    foreach (i, ignore ; typeof(BasicTypes.tupleof)) {
      static if(isNumeric!(typeof(BasicTypes.tupleof[i]))) {
        static if(isFloatingPoint!(typeof(BasicTypes.tupleof[i]))) {
          bt1.tupleof[i] = bt2.tupleof[i] = 3;
        }
        bt2.tupleof[i]++;
        assert(bt1.toHash() != bt2.toHash());
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
          static assert(false, "CT: Deal with "~BasicTypes.tupleof[i]);
        }
    }

// end <basic_type_coveragetest_coverage>
  }
}

class InfinniteLoop { 
  mixin TestMixin;
  /**
     One grabs the other, the other grabs the one - was causing infinite loop
  */
  struct PartGrabbers { 
    mixin HashSupport;
    alias PartGrabbers* PartGrabbersPtr;
    PartGrabbersPtr other;
    int extra = 3;
    
// custom <dstruct part_grabbers public_section>
// end <dstruct part_grabbers public_section>
  }


  void testTypesDeepEqualLoop() {
  
// custom <infinnite_looptest_types_deep_equal_loop>

    PartGrabbers pg1, pg2;
    pg1.other = &pg2;
    pg2.other = &pg1;
    assert(pg1 == pg2);
    pg1.extra++;
    assert(pg1 != pg2);
    pg2.extra++;
    assert(pg1 == pg2);  
    assert(typesDeepEqual(pg1, pg2));
    pg2.other = null;
    assert(!typesDeepEqual(pg1, pg2));
    pg1.other = null;
    assert(typesDeepEqual(pg1, pg2));

// end <infinnite_looptest_types_deep_equal_loop>
  }
}

class HeavyNesting { 
  mixin TestMixin;
  /**
     Top level class with nested classes for testing HashSupport(OpCmp and OpEquals) and Dup.
  */
  struct A { 
    mixin HashSupport;
    mixin Dup;
    alias string[string] SSMap;
    alias B[B] BBMap;
    alias int* IntPtr;
    alias B* BPtr;
    struct B { 
      mixin HashSupport;
      mixin Dup;
      
// custom <dstruct b public_section>
// end <dstruct b public_section>

      private {
        char[] _bw;
        string _bx = "foo";
        int _by = 3;
        string _bz = "zoo";
      }
    }

    
// custom <dstruct a public_section>
// end <dstruct a public_section>

    private {
      char[] _w;
      string _x = "foo";
      int _y = 3;
      string _z = "zoo";
      B _b;
      SSMap _map;
      BBMap _bMap;
      BPtr _bPtr;
      IntPtr _intPtr;
    }
  }


  void testNesting() {
  
// custom <heavy_nestingtest_nesting>

    // Create s.t. a==b and a!=c
    auto ss1 = [ "grape".idup : "vine".idup ];
    auto ss2 = [ "grape".idup : "vine".idup ];
    A a, b, c = { _w : ['a','b'], _x : "goo".idup, _map : ss1 };
    // Copy same string different address keeping a==b
    b._x = "foo".idup;

    assert(a.toHash() && (a.toHash() == a.dup.toHash()));

    // Similar for const objects
    const(A) ca, cb, cc = { _w : ['a','b'], _x : "goo".idup, _map : ss2 };

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

    auto zoo1 = Zoo(['x','y','z'].dup);
    auto zoo2 = Zoo(['x','y','z'].dup);
    assert(zoo1 == zoo2);

// end <heavy_nestingtest_nesting>
  }
}


void main() {
  dunit.runTests_Tree();
}


// custom <dmodule mix public_section>

struct Zoo {
  char c[];
  mixin OpEquals;
}

static void equalHashSanity(T)(const ref T lhs, const ref T rhs) {
  assertEquals(lhs, rhs);    
  assert(!(lhs<rhs));
  assert(!(rhs>lhs));
  auto h1 = lhs.toHash();
  assert(h1);
  assertEquals(h1, lhs.dup.toHash());
  assertEquals(h1, rhs.toHash());
}

// end <dmodule mix public_section>

/**
   License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
*/
