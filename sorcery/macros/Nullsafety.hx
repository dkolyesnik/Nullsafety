package sorcery.macros;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.ModuleType;
import haxe.macro.Type.TConstant;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TypedExprDef;
import haxe.macro.TypedExprTools;
using haxe.macro.ExprTools;
/**
 * ...
 * @author Dmitriy Kolesnik
 */

class Nullsafety
{
	#if macro
	static function log(msg:Dynamic)
	{
		//trace(msg);
	}
	#end

	/* some issues
	 * Will not check if the fiels that is called as function is not null
	 * so in case of function type field like
	 * class SomeClass {
	 * 		public var f:Void->Void;
	 * }
	 * there will be an runtime error if f is a null
	 * Parentses can be uset to bypass this if it is a start of the expr:
	 * safeGet((SomeClass.f)()) - this way it will check if SomeClass.f != null
	 *
	 * */

	/**
	 * nullsafe binop execution, will generate checks for the right expr
	 * and binop will be executed only if all checks are passed
	 * retruns true if binop is executed, false otherwise
	 */
	macro public static function safeBOp(value:Expr)
	{
		log("--------------safeBOp------------------");
		log(Std.string(value.pos));
		log(value);

		var leftExpr;
		var binop;
		switch (value.expr)
		{
			case EBinop(binop, leftExpr, rightExpr):
				var defaultTypeValue = getDefaultTypeValue(rightExpr);
				var resultExpr = _doit(rightExpr, CTSafeGet(defaultTypeValue, defaultTypeValue));
				switch (resultExpr.expr)
				{
					case EBlock(a):
						var binopExpr = {expr:EBinop(binop, leftExpr, macro $i{_resName}), pos:value.pos};
						a.push(macro if ($i {_flagName}) $binopExpr);
						a.push(macro $i {_flagName});
					default:
						resultExpr = macro {$resultExpr ; true;};
				}
				return resultExpr;
			default:
				throw "Error: wrong expr";
		}
		return value;
	}

	/**
	 * nullsafe chained calls
	 * return true if last expression is executed, false otherwise
	 * return value of the last expression is not checked, it can be any type
	 * generate a number of (if != null) checks and local variables
	 * no anonymous objects, functions and so on, strictly typed
	 * wrapping part of the chain in parentheses will make it the fist check condition
	 * i.e. safeCall((a.b.c).d) will generate one check if(a.b.c != null)
	 * @param	value  -  call chain
	 */
	@:noUsing
	macro public static function safeCall(value:Expr)
	{
		log("--------------safeCall------------------");
		log(Std.string(value.pos));
		log(value);

		return _doit(value, CTSafeCall);
	}

	/**
	 * nullsafe chained calls to get some value,
	 * if any call returns null returns defaultValue
	 * generate a number of (if != null) checks and local variables
	 * no anonymous objects, functions and so on, strictly typed
	 * in case of assignment in assighn call chain value or defaulVelue to a variable
	 * and returns true/false
	 * @param	value  -  chain to get a value
	 * @param	defaultValue  - default expression
	 */
	@:noUsing
	macro public static function safeGet(value:Expr, ?defaultValue:Expr)
	{
		log("--------------safeGet------------------");
		log(Std.string(value.pos));
		log(value);
		log(defaultValue);

		var returnType = Context.typeExpr(value).t;
		var isNullable = false;
		var defaultTypeValue = switch (returnType)
		{
			case TAbstract(_.get()=> {name:"Int"}, _):
				macro 0;
			case TAbstract(_.get() => {name:"Float"}, _):
				macro 0.0;
			case TAbstract(_.get() => {name:"Bool"}, _):
				macro false;
			case TAbstract(_.get() => {name:"Void"}, _):
				throw "Error: expression must be not Void";
			default:
				isNullable = true;
				macro null;
		}
		switch (defaultValue.expr)
		{
			case EConst(CIdent(_ => "null")):
				defaultValue = null;
			default:
		}

		return _doit(value, isNullable ? CTSafeGetNull(defaultValue) : CTSafeGet(defaultTypeValue, defaultValue));
	}
	#if macro
	static var _varPref = "__n_";
	static var _flagName = _varPref + "f";
	static var _resName = _varPref + "r";

	public static function _doit(value:Expr, callType:CallType )
	{
		log(callType.getName());

		var exprArray = [];
		switch (value.expr)
		{
			case EArray(e, _) | EField(e, _) | ECall(e, _):
				exprArray.push(value);
				unwrapExpr(e, exprArray);
			default:
				throw "Error: wrong expression";
		}
		if (exprArray.length == 0)
			throw "Error: need more expressions";

		var createVarName:Void->String;
		var parseExpr:Expr->String->Expr;
		var createNextTempVarAndIf:Expr->Expr;
		var createFinalIfBody:Expr->Expr;
		var varCounter = 0;
		createVarName = function() return _varPref + Std.string(++varCounter);

		createNextTempVarAndIf = function(exprCall:Expr)
		{
			var newVar = createVarName();
			return macro
			{
				var $newVar = $exprCall;
				if ($i{newVar} != null)
				{
					$ {parseExpr(exprArray.pop(), newVar)};
				}
			};
		};

		createFinalIfBody = function(exprCall:Expr)
		{
			switch (callType)
			{
				case CTSafeCall:
					return macro { $exprCall; $i{_flagName} = true; };
				case CTSafeGet(_, _=>null):
					return macro $i {_resName} = $exprCall;
				case CTSafeGet(_, _):
					return macro { $i{_resName} = $exprCall; $i{_flagName} = true;};
				case CTSafeGetNull(_):
					return macro $i {_resName} = $exprCall;
			}
		};

		parseExpr = function(expr:Expr, prevVar:String)
		{
			switch (expr.expr)
			{
				case EField(e, f):
					if (exprArray.length > 0)
					{
						var nextExpr = exprArray[exprArray.length - 1];
						switch (nextExpr.expr)
						{
							case ECall(e, p):
								//if there is a call after field, do not check fiels alone
								exprArray.pop();
								var callExpr = {expr:ECall(macro $i{prevVar} .$f, p), pos:expr.pos};
								if (exprArray.length > 0)
									return createNextTempVarAndIf(callExpr);
								else
									return createFinalIfBody(callExpr);
							default:
								return createNextTempVarAndIf(macro $i {prevVar} .$f);

						}
					}
					else
						return createFinalIfBody(macro $i {prevVar} .$f);
				case ECall(e, p):
					//possible only after parentses or other call or array
					var callExpr = {expr:ECall(macro $i{prevVar}, p), pos:e.pos};
					if (exprArray.length > 0)
						return createNextTempVarAndIf(callExpr);
					else
						return createFinalIfBody(callExpr);
				case EArray(e1, e2):
					var callExpr = macro $i {prevVar} [$e2];
					if (exprArray.length > 0)
						return createNextTempVarAndIf(callExpr);
					else
						return createFinalIfBody(callExpr);
				default:
					throw "Error";
			}
		};
		var firstExpr = exprArray.pop();
		var firstCheckedExpr;
		switch (firstExpr.expr)
		{
			case EField(e, f):
				firstCheckedExpr = macro $i {f};
			case EParenthesis(e):
				firstCheckedExpr = e;
			case EConst(CIdent(s)):
				if (isIdentifierAThisOrTypeExpr(firstExpr))
				{
					if (exprArray.length > 0)
					{
						var nextExpr = exprArray.pop();
						switch (nextExpr.expr)
						{
							case EField(e, f):
								if (exprArray.length > 0)
								{
									var nextNextExpr = exprArray[exprArray.length-1];
									switch (nextNextExpr.expr)
									{
										case ECall(ec, p):
											exprArray.pop();
											firstCheckedExpr = {expr:ECall(macro $i{s} .$f, p), pos:ec.pos};
										default:
											firstCheckedExpr = macro $i {s} .$f;
									}
								}
								else
								{
									firstCheckedExpr = macro $i {s} .$f;
								}
							default:
								throw "Error";
						}
					}
					else
					{
						throw "Error";
					}
				}
				else
				{
					firstCheckedExpr = macro $i {s};
				}
			default:
				throw "Error";
		}
		switch (callType)
		{
			case CTSafeCall:
				return macro
				{
					var $_flagName = false;
					${createNextTempVarAndIf(firstCheckedExpr)};
					$i{_flagName};
				};
			case CTSafeGet(dtv, _ => null):
				return macro
				{
					var $_resName = $dtv;
					${createNextTempVarAndIf(firstCheckedExpr)};
					$i{_resName};
				};
			case CTSafeGet(dtv, dv):
				return macro
				{
					var $_flagName = false;
					var $_resName = $dtv;
					${createNextTempVarAndIf(firstCheckedExpr)};
					if (!$i{_flagName})
						$i{_resName} = $dv;
					$i{_resName};
				};
			case CTSafeGetNull(_=>null):
				return macro
				{
					var $_resName = null;
					${createNextTempVarAndIf(firstCheckedExpr)};
					$i{_resName};
				};
			case CTSafeGetNull(dv):
				return macro
				{
					var $_resName = null;
					${createNextTempVarAndIf(firstCheckedExpr)};
					if ($i{_resName} == null)
						$i{_resName} = $dv;
					$i{_resName};
				};
		}

	}

	static function unwrapExpr(expr:Expr, ar:Array<Expr>)
	{
		ar.push(expr);
		switch (expr.expr)
		{
			case EField(e, _) | EArray(e,_) | ECall(e,_):
				unwrapExpr(e, ar);
			case EConst(_)|EParenthesis(_):
			default:
				throw "Error: this type of expression is not supported";
		}
	}

	static function isIdentifierAThisOrTypeExpr(expr:Expr) :Bool
	{
		var te = Context.typeExpr(expr);
		return switch (te.expr)
		{
			case TConst(TThis) | TTypeExpr(_):
				true;
			default:
				false;
		}
	}

	static function getDefaultTypeValue(value:Expr)
	{
		return switch (Context.typeExpr(value).t)
		{
			case TAbstract(_.get()=> {name:"Int"}, _):
				macro 0;
			case TAbstract(_.get() => {name:"Float"}, _):
				macro 0.0;
			case TAbstract(_.get() => {name:"Bool"}, _):
				macro false;
			case TAbstract(_.get() => {name:"Void"}, _):
				throw "Error: expression must be not Void";
			default:
				macro null;
		}

	}
	#end
}

#if macro
private enum CallType
{
	CTSafeCall;
	CTSafeGet(defTypeValue:Expr, defValue:Expr);
	CTSafeGetNull(defValue:Expr);
}
#end

