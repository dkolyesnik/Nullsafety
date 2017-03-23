# Nullsafety
Macro functions to convert long chain of calls into if( x != null ) checks

Chained calls can have field accesses, function calls and array accesses.
First expression of the array access is checked too, functions are called without checking if it is null

some().long[0].chain  - will check some() != null, long != null, long[0] !=null

Parenthesis
(some.long).chain - will check expression in Parenthesis and the rest of the call: some.long != null, chain != null


safeCall
-----------------
Returns true if all calls were made. This way
```haxe
if(safeCall(some.long.chain)) {
}
``` will be transformed into
```haxe
  var __f = false;
  if(some != null) {
    var __0 = some.long;
    if(__0 != null){
       __0.chain;
       __f = true;
     }
  }
if(_f){
  
}
```
safeGet
-----------------
Returns the result of the chained calls or default value.
For nullable type
Will check the result of the last call as well and return default value if it is null
For Int, Float, Bool
Will not check the result of the last call. In case if default value is omitted, returns 0 , 0.0, false
```haxe
var x = safeGet(some.long.chain.x, 10);
```will be transformed into
```haxe
var __f = false;
var __r = 0;
if(some != null) {
var __0 = some.long;
  if(__0 != null){
    var __1 = __0.chain;
    if(__1 != null){
      __r = __1.x;
      __f = true;
    }
  }
}
if(!__f)
  __r = 10;
var x = __r;
```
