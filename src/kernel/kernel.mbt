// ///|
// struct Context {
//   args : Array[@type.Type]
//   args_cache : Map[@type.TypedImmutArray, Int]
//   mut tmps : Int
//   tmps_cache : Map[@expr.Expr, Int]
// }

// ///|
// pub fn Context::new() -> Context {
//   Context::{
//     args: Array::new(),
//     args_cache: Map::new(),
//     tmps: 0,
//     tmps_cache: Map::new(),
//   }
// }

// ///|
// pub fn Context::get_arg[T : @type.FixedToImmut](
//   self : Context,
//   value : FixedArray[T]
// ) -> @expr.Var {
//   let immut_value = @type.FixedToImmut::to_immut(value)
//   guard let None = self.args_cache[immut_value] else {
//     Some(arg_id) => return @expr.arg(arg_id)
//   }
//   let arg_id = self.args.length()
//   self.args.push(@type.ptr_i32)
//   self.args_cache[immut_value] = arg_id
//   @expr.arg(arg_id)
// }

// ///|
// pub fn Context::get_tmp(self : Context, expr : @expr.Expr) -> @expr.Var {
//   guard let None = self.tmps_cache[expr] else {
//     Some(tmp_id) => return @expr.tmp(tmp_id)
//   }
//   let tmp_id = self.tmps
//   self.tmps += 1
//   self.tmps_cache[expr] = tmp_id
//   @expr.tmp(tmp_id)
// }
