// RUN: triton-opt %s -split-input-file -tritongpu-remove-layout-conversions 2>&1 | FileCheck %s

#layout0 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
#layout1 = #triton_gpu.blocked<{sizePerThread = [4], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>

#layout2 = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [2, 16], warpsPerCTA = [4, 1], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
#layout3 = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [2, 16], warpsPerCTA = [1, 4], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>


module attributes {"triton_gpu.num-warps" = 4 : i32} {

// CHECK: [[$target_layout:#.*]] = #triton_gpu.blocked<{sizePerThread = [4], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
// CHECK-LABEL: cst
tt.func @cst() -> tensor<1024xi32, #layout1> {
  %cst = arith.constant dense<0> : tensor<1024xi32, #layout0>
  %1 = triton_gpu.convert_layout %cst : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
  // CHECK-NOT: triton_gpu.convert_layout
  // CHECK: tt.return %cst : tensor<1024xi32, [[$target_layout]]>
  tt.return %1: tensor<1024xi32, #layout1>
}

// CHECK-LABEL: range
tt.func @range() -> tensor<1024xi32, #layout1> {
  %0 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, #layout0>
  %1 = triton_gpu.convert_layout %0 : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
  // CHECK-NOT: triton_gpu.convert_layout
  // CHECK: tt.return %0 : tensor<1024xi32, [[$target_layout]]>
  tt.return %1: tensor<1024xi32, #layout1>
}

// CHECK-LABEL: splat
tt.func @splat(%arg0: i32) -> tensor<1024xi32, #layout1> {
  %0 = tt.splat %arg0 : (i32) -> tensor<1024xi32, #layout0>
  %1 = triton_gpu.convert_layout %0 : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
  // CHECK-NOT: triton_gpu.convert_layout
  // CHECK: tt.return %0 : tensor<1024xi32, [[$target_layout]]>
  tt.return %1: tensor<1024xi32, #layout1>
}

// CHECK-LABEL: remat
tt.func @remat(%arg0: i32) -> tensor<1024xi32, #layout1> {
  %0 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, #layout0>
  %1 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, #layout0>
  %2 = arith.muli %0, %1 : tensor<1024xi32, #layout0>
  %3 = triton_gpu.convert_layout %2 : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
  %4 = tt.splat %arg0 : (i32) -> tensor<1024xi32, #layout0>
  %5 = triton_gpu.convert_layout %2 : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
  %6 = arith.addi %3, %5 : tensor<1024xi32, #layout1>
  tt.return %6: tensor<1024xi32, #layout1>
  // CHECK: %0 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, [[$target_layout]]>
  // CHECK: %1 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, [[$target_layout]]>
  // CHECK: %2 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, [[$target_layout]]>
  // CHECK: %3 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, [[$target_layout]]>
  // CHECK: %4 = arith.muli %0, %2 : tensor<1024xi32, [[$target_layout]]>
  // CHECK: %5 = arith.muli %1, %3 : tensor<1024xi32, [[$target_layout]]>
  // CHECK: %6 = arith.addi %4, %5 : tensor<1024xi32, [[$target_layout]]>
  // CHECK: tt.return %6 : tensor<1024xi32, [[$target_layout]]>
}

// Always rematerialize single value loads
// CHECK-LABEL: remat_single_value
tt.func @remat_single_value(%arg: !tt.ptr<i32> {tt.divisibility = 16 : i32}) {
  %0 = tt.splat %arg : (!tt.ptr<i32>) -> tensor<1x!tt.ptr<i32>, #layout1>
  %1 = tt.load %0 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1xi32, #layout1>
  // CHECK-NOT: triton_gpu.convert_layout
  %2 = triton_gpu.convert_layout %1 : (tensor<1xi32, #layout1>) -> tensor<1xi32, #layout0>
  %3 = triton_gpu.convert_layout %0 : (tensor<1x!tt.ptr<i32>, #layout1>) -> tensor<1x!tt.ptr<i32>, #layout0>
  tt.store %3, %2 : tensor<1xi32, #layout0>
  tt.return
}

tt.func @remat_fast_load(%arg: !tt.ptr<i32> {tt.divisibility = 16 : i32}) {
  %0 = tt.splat %arg : (!tt.ptr<i32>) -> tensor<16x!tt.ptr<i32>, #layout1>
  %1 = tt.make_range {end = 16 : i32, start = 0 : i32} : tensor<16xi32, #layout1>
  %2 = tt.addptr %0, %1 : tensor<16x!tt.ptr<i32>, #layout1>, tensor<16xi32, #layout1>
  %3 = tt.load %2 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16xi32, #layout1>
  // CHECK-NOT: triton_gpu.convert_layout
  %4 = triton_gpu.convert_layout %3 : (tensor<16xi32, #layout1>) -> tensor<16xi32, #layout0>
  %5 = triton_gpu.convert_layout %2 : (tensor<16x!tt.ptr<i32>, #layout1>) -> tensor<16x!tt.ptr<i32>, #layout0>
  tt.store %5, %4 : tensor<16xi32, #layout0>
  tt.return
}

// Hoist the convert on top of ext to make it cheaper.
// CHECK-LABEL: hoist_above_ext
tt.func @hoist_above_ext(%arg0: tensor<1024xf16, #layout0>, %arg1: f32) -> tensor<1024xf32, #layout1> {
// CHECK: %[[CVT:.+]] = triton_gpu.convert_layout
// CHECK: arith.extf %[[CVT]]
// CHECK-NOT: triton_gpu.convert_layout
// CHECK: tt.return
  %0 = arith.extf %arg0 : tensor<1024xf16, #layout0> to tensor<1024xf32, #layout0>
  %1 = tt.splat %arg1 : (f32) -> tensor<1024xf32, #layout0>
  %2 = arith.addf %0, %1 : tensor<1024xf32, #layout0>
  %3 = triton_gpu.convert_layout %2 : (tensor<1024xf32, #layout0>) -> tensor<1024xf32, #layout1>
  tt.return %3 : tensor<1024xf32, #layout1>
}

// CHECK-LABEL: hoist_above_ext2
tt.func @hoist_above_ext2(%arg0: tensor<1024xf16, #layout0>, %arg1: f16) -> tensor<1024xf32, #layout1> {
// CHECK: %[[CVT:.+]] = triton_gpu.convert_layout
// CHECK: arith.extf %[[CVT]]
// CHECK-NOT: triton_gpu.convert_layout
// CHECK: tt.return
  %0 = arith.extf %arg0 : tensor<1024xf16, #layout0> to tensor<1024xf32, #layout0>
  %1 = tt.splat %arg1 : (f16) -> tensor<1024xf16, #layout0>
  %2 = arith.extf %1 : tensor<1024xf16, #layout0> to tensor<1024xf32, #layout0>
  %3 = arith.addf %0, %2 : tensor<1024xf32, #layout0>
  %4 = triton_gpu.convert_layout %3 : (tensor<1024xf32, #layout0>) -> tensor<1024xf32, #layout1>
  tt.return %4 : tensor<1024xf32, #layout1>
}

// Hoist the convert on top of broadcast to make it cheaper.
// CHECK-LABEL: hoist_above_broadcast
tt.func @hoist_above_broadcast(%arg0: tensor<1024x1xf32, #layout2>, %arg1: f32) -> tensor<1024x128xf32, #layout3> {
// CHECK: %[[CVT:.+]] = triton_gpu.convert_layout
// CHECK: tt.broadcast %[[CVT]]
// CHECK-NOT: triton_gpu.convert_layout
// CHECK: tt.return
  %0 = tt.broadcast %arg0 : (tensor<1024x1xf32, #layout2>) -> tensor<1024x128xf32, #layout2>
  %1 = tt.splat %arg1 : (f32) -> tensor<1024x128xf32, #layout2>
  %2 = arith.addf %0, %1 : tensor<1024x128xf32, #layout2>
  %3 = triton_gpu.convert_layout %2 : (tensor<1024x128xf32, #layout2>) -> tensor<1024x128xf32, #layout3>
  tt.return %3 : tensor<1024x128xf32, #layout3>
}


// CHECK-LABEL: if
tt.func @if(%arg0: i32, %arg1: !tt.ptr<i32> {tt.divisibility = 16 : i32}) {
  // CHECK-NOT: triton_gpu.convert_layout
  %c32_i32 = arith.constant dense<32> : tensor<1024xi32, #layout1>
  %0 = tt.get_program_id x : i32
  %1 = tt.splat %0 : (i32) -> tensor<1024xi32, #layout1>
  %2 = arith.muli %1, %c32_i32 : tensor<1024xi32, #layout1>
  %3 = arith.addi %2, %c32_i32 : tensor<1024xi32, #layout1>
  %4 = arith.cmpi sgt, %0, %arg0 : i32
  %5 = tt.splat %arg1 : (!tt.ptr<i32>) -> tensor<1024x!tt.ptr<i32>, #layout0>
  scf.if %4 {
    %6 = triton_gpu.convert_layout %2 : (tensor<1024xi32, #layout1>) -> tensor<1024xi32, #layout0>
    tt.store %5, %6 : tensor<1024xi32, #layout0>
  }
  tt.return
}

// CHECK-LABEL: if_convert_else_not
tt.func @if_convert_else_not(%arg0: i32, %arg1: !tt.ptr<i32> {tt.divisibility = 16 : i32}) {
  %c32_i32 = arith.constant dense<32> : tensor<1024xi32, #layout0>
  %0 = tt.get_program_id x : i32
  %1 = tt.splat %0 : (i32) -> tensor<1024xi32, #layout0>
  %9 = tt.splat %0 : (i32) -> tensor<1024xi32, #layout1>
  %2 = arith.muli %1, %c32_i32 : tensor<1024xi32, #layout0>
  %3 = arith.addi %2, %c32_i32 : tensor<1024xi32, #layout0>
  %4 = arith.cmpi sgt, %0, %arg0 : i32
  %5 = tt.splat %arg1 : (!tt.ptr<i32>) -> tensor<1024x!tt.ptr<i32>, #layout1>
  %8 = scf.if %4 -> tensor<1024xi32, #layout1> {
    %6 = triton_gpu.convert_layout %2 : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
    scf.yield %6 : tensor<1024xi32, #layout1>
  } else {
    scf.yield %9 : tensor<1024xi32, #layout1>
  }
  // CHECK-NOT: triton_gpu.convert_layout
  tt.store %5, %8 : tensor<1024xi32, #layout1>
  tt.return
}

// CHECK-LABEL: if_not_else_convert
tt.func @if_not_else_convert(%arg0: i32, %arg1: !tt.ptr<i32> {tt.divisibility = 16 : i32}) {
  %c32_i32 = arith.constant dense<32> : tensor<1024xi32, #layout0>
  %0 = tt.get_program_id x : i32
  %1 = tt.splat %0 : (i32) -> tensor<1024xi32, #layout0>
  %9 = tt.splat %0 : (i32) -> tensor<1024xi32, #layout1>
  %2 = arith.muli %1, %c32_i32 : tensor<1024xi32, #layout0>
  %3 = arith.addi %2, %c32_i32 : tensor<1024xi32, #layout0>
  %4 = arith.cmpi sgt, %0, %arg0 : i32
  %5 = tt.splat %arg1 : (!tt.ptr<i32>) -> tensor<1024x!tt.ptr<i32>, #layout1>
  %8 = scf.if %4 -> tensor<1024xi32, #layout1> {
    scf.yield %9 : tensor<1024xi32, #layout1>
  } else {
    %7 = triton_gpu.convert_layout %3 : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
    scf.yield %7 : tensor<1024xi32, #layout1>
  }
  // CHECK-NOT: triton_gpu.convert_layout
  tt.store %5, %8 : tensor<1024xi32, #layout1>
  tt.return
}

// CHECK-LABEL: if_else_both_convert
tt.func @if_else_both_convert(%arg0: i32, %arg1: !tt.ptr<i32> {tt.divisibility = 16 : i32}) {
  %c32_i32 = arith.constant dense<32> : tensor<1024xi32, #layout0>
  %0 = tt.get_program_id x : i32
  %1 = tt.splat %0 : (i32) -> tensor<1024xi32, #layout0>
  %2 = arith.muli %1, %c32_i32 : tensor<1024xi32, #layout0>
  %3 = arith.addi %2, %c32_i32 : tensor<1024xi32, #layout0>
  %4 = arith.cmpi sgt, %0, %arg0 : i32
  %5 = tt.splat %arg1 : (!tt.ptr<i32>) -> tensor<1024x!tt.ptr<i32>, #layout1>
  %8 = scf.if %4 -> tensor<1024xi32, #layout1> {
    %6 = triton_gpu.convert_layout %2 : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
    scf.yield %6 : tensor<1024xi32, #layout1>
  } else {
    %7 = triton_gpu.convert_layout %3 : (tensor<1024xi32, #layout0>) -> tensor<1024xi32, #layout1>
    scf.yield %7 : tensor<1024xi32, #layout1>
  }
  // TODO(csigg): seems like the whole function is converted to layout1.
  // disabledCHECK: triton_gpu.convert_layout
  // CHECK-NOT: triton_gpu.convert_layout
  tt.store %5, %8 : tensor<1024xi32, #layout1>
  tt.return
}

}

// -----

#blocked0 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [4, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
#slice1dim1 = #triton_gpu.slice<{dim = 1, parent = #blocked1}>
#blocked2 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 4], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
#slice2dim0 = #triton_gpu.slice<{dim = 0, parent = #blocked2}>
#blocked3 = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [2, 16], warpsPerCTA = [1, 4], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked4 = #triton_gpu.blocked<{sizePerThread = [4, 1], threadsPerWarp = [16, 2], warpsPerCTA = [4, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
#blocked5 = #triton_gpu.blocked<{sizePerThread = [4], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>

// CHECK: [[$row_layout:#.*]] = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [2, 16], warpsPerCTA = [1, 4], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
// CHECK: [[$col_layout:#.*]] = #triton_gpu.blocked<{sizePerThread = [4, 1], threadsPerWarp = [16, 2], warpsPerCTA = [4, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
// CHECK: [[$col_layout_novec:#.*]] = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [4, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>

// CHECK-LABEL: @transpose
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func @transpose(%arg0: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg1: i32 {tt.divisibility = 16 : i32}, %arg2: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg3: i32 {tt.divisibility = 16 : i32}) {
  // CHECK-NOT: triton_gpu.convert_layout
  // CHECK: [[loaded_val:%.*]] = tt.load {{.*}}, {{%cst.*}}, {{%cst.*}} {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<64x64xf32, [[$row_layout]]>
  // CHECK: [[cvt_val:%.*]] = triton_gpu.convert_layout [[loaded_val]] : (tensor<64x64xf32, [[$row_layout]]>) -> tensor<64x64xf32, [[$col_layout]]>
  // CHECK: tt.store {{.*}}, [[cvt_val]], {{%cst.*}} : tensor<64x64xf32, [[$col_layout]]>
  // CHECK: tt.return
  %cst = arith.constant dense<0.000000e+00> : tensor<64x64xf32, #blocked1>
  %cst_0 = arith.constant dense<true> : tensor<64x64xi1, #blocked1>
  %00 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #slice1dim1>
  %01 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #slice2dim0>
  %1 = tt.expand_dims %00 {axis = 1 : i32} : (tensor<64xi32, #slice1dim1>) -> tensor<64x1xi32, #blocked1>
  %2 = tt.splat %arg1 : (i32) -> tensor<64x1xi32, #blocked1>
  %3 = arith.muli %1, %2 : tensor<64x1xi32, #blocked1>
  %4 = tt.splat %arg0 : (!tt.ptr<f32>) -> tensor<64x1x!tt.ptr<f32>, #blocked1>
  %5 = tt.addptr %4, %3 : tensor<64x1x!tt.ptr<f32>, #blocked1>, tensor<64x1xi32, #blocked1>
  %6 = tt.expand_dims %01 {axis = 0 : i32} : (tensor<64xi32, #slice2dim0>) -> tensor<1x64xi32, #blocked2>
  %7 = tt.broadcast %5 : (tensor<64x1x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked1>
  %8 = tt.broadcast %6 : (tensor<1x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %9 = triton_gpu.convert_layout %8 : (tensor<64x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked1>
  %10 = tt.addptr %7, %9 : tensor<64x64x!tt.ptr<f32>, #blocked1>, tensor<64x64xi32, #blocked1>
  %11 = tt.splat %arg2 : (!tt.ptr<f32>) -> tensor<64x1x!tt.ptr<f32>, #blocked1>
  %12 = tt.addptr %11, %1 : tensor<64x1x!tt.ptr<f32>, #blocked1>, tensor<64x1xi32, #blocked1>
  %13 = tt.splat %arg3 : (i32) -> tensor<1x64xi32, #blocked2>
  %14 = arith.muli %6, %13 : tensor<1x64xi32, #blocked2>
  %15 = tt.broadcast %12 : (tensor<64x1x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked1>
  %16 = tt.broadcast %14 : (tensor<1x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %17 = triton_gpu.convert_layout %16 : (tensor<64x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked1>
  %18 = tt.addptr %15, %17 : tensor<64x64x!tt.ptr<f32>, #blocked1>, tensor<64x64xi32, #blocked1>
  %19 = triton_gpu.convert_layout %10 : (tensor<64x64x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked3>
  %20 = triton_gpu.convert_layout %cst_0 : (tensor<64x64xi1, #blocked1>) -> tensor<64x64xi1, #blocked3>
  %21 = triton_gpu.convert_layout %cst : (tensor<64x64xf32, #blocked1>) -> tensor<64x64xf32, #blocked3>
  %22 = tt.load %19, %20, %21 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<64x64xf32, #blocked3>
  %23 = triton_gpu.convert_layout %22 : (tensor<64x64xf32, #blocked3>) -> tensor<64x64xf32, #blocked1>
  %24 = triton_gpu.convert_layout %18 : (tensor<64x64x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked4>
  %25 = triton_gpu.convert_layout %23 : (tensor<64x64xf32, #blocked1>) -> tensor<64x64xf32, #blocked4>
  %26 = triton_gpu.convert_layout %cst_0 : (tensor<64x64xi1, #blocked1>) -> tensor<64x64xi1, #blocked4>
  tt.store %24, %25, %26 : tensor<64x64xf32, #blocked4>
  tt.return
}
}

// CHECK-LABEL: loop
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func @loop(%arg0: !tt.ptr<f32>, %arg1: i32, %arg2: !tt.ptr<f32>, %arg3: i32, %arg4: i32) {
  // CHECK-NOT: triton_gpu.convert_layout
  // CHECK: [[loop_ret:%.*]]:2 = scf.for {{.*}} -> (tensor<64x64xf32, [[$row_layout]]>, tensor<64x64x!tt.ptr<f32, 1>, [[$row_layout]]>)
  // CHECK-NEXT: {{.*}} = tt.load {{.*}} : tensor<64x64xf32, [[$row_layout]]>
  // CHECK-NEXT: {{.*}} = arith.addf {{.*}} : tensor<64x64xf32, [[$row_layout]]>
  // CHECK-NEXT: {{.*}} = tt.addptr {{.*}} : tensor<64x64x!tt.ptr<f32, 1>, [[$row_layout]]>, tensor<64x64xi32, [[$row_layout]]>
  // CHECK-NEXT: scf.yield {{.*}} : tensor<64x64xf32, [[$row_layout]]>, tensor<64x64x!tt.ptr<f32, 1>, [[$row_layout]]>
  // CHECK-NEXT: }
  // CHECK-NOT: triton_gpu.convert_layout
  //     CHECK: {{.*}} = triton_gpu.convert_layout [[loop_ret]]#0 : (tensor<64x64xf32, [[$row_layout]]>) -> tensor<64x64xf32, [[$col_layout_novec]]>
  // CHECK-NOT: triton_gpu.convert_layout
  //    CHECK:  tt.return
  %cst = arith.constant dense<true> : tensor<64x64xi1, #blocked1>
  %cst_0 = arith.constant dense<64> : tensor<64x64xi32, #blocked1>
  %c1 = arith.constant 1 : index
  %c32 = arith.constant 32 : index
  %c0 = arith.constant 0 : index
  %cst_1 = arith.constant dense<0.000000e+00> : tensor<64x64xf32, #blocked1>
  %00 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #slice1dim1>
  %01 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #slice2dim0>
  %1 = tt.expand_dims %00 {axis = 1 : i32} : (tensor<64xi32, #slice1dim1>) -> tensor<64x1xi32, #blocked1>
  %2 = tt.splat %arg1 : (i32) -> tensor<64x1xi32, #blocked1>
  %3 = arith.muli %1, %2 : tensor<64x1xi32, #blocked1>
  %4 = tt.splat %arg0 : (!tt.ptr<f32>) -> tensor<64x1x!tt.ptr<f32>, #blocked1>
  %5 = tt.addptr %4, %3 : tensor<64x1x!tt.ptr<f32>, #blocked1>, tensor<64x1xi32, #blocked1>
  %6 = tt.expand_dims %01 {axis = 0 : i32} : (tensor<64xi32, #slice2dim0>) -> tensor<1x64xi32, #blocked2>
  %7 = tt.broadcast %5 : (tensor<64x1x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked1>
  %8 = tt.broadcast %6 : (tensor<1x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %9 = triton_gpu.convert_layout %8 : (tensor<64x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked1>
  %10 = tt.addptr %7, %9 : tensor<64x64x!tt.ptr<f32>, #blocked1>, tensor<64x64xi32, #blocked1>
  %11:2 = scf.for %arg5 = %c0 to %c32 step %c1 iter_args(%arg6 = %cst_1, %arg7 = %10) -> (tensor<64x64xf32, #blocked1>, tensor<64x64x!tt.ptr<f32>, #blocked1>) {
    %23 = triton_gpu.convert_layout %arg7 : (tensor<64x64x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked3>
    %24 = triton_gpu.convert_layout %cst : (tensor<64x64xi1, #blocked1>) -> tensor<64x64xi1, #blocked3>
    %25 = triton_gpu.convert_layout %cst_1 : (tensor<64x64xf32, #blocked1>) -> tensor<64x64xf32, #blocked3>
    %26 = tt.load %23, %24, %25 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<64x64xf32, #blocked3>
    %27 = triton_gpu.convert_layout %26 : (tensor<64x64xf32, #blocked3>) -> tensor<64x64xf32, #blocked1>
    %28 = arith.addf %arg6, %27 : tensor<64x64xf32, #blocked1>
    %29 = tt.addptr %arg7, %cst_0 : tensor<64x64x!tt.ptr<f32>, #blocked1>, tensor<64x64xi32, #blocked1>
    scf.yield %28, %29 : tensor<64x64xf32, #blocked1>, tensor<64x64x!tt.ptr<f32>, #blocked1>
  }
  %12 = tt.splat %arg2 : (!tt.ptr<f32>) -> tensor<64x1x!tt.ptr<f32>, #blocked1>
  %13 = tt.addptr %12, %1 : tensor<64x1x!tt.ptr<f32>, #blocked1>, tensor<64x1xi32, #blocked1>
  %14 = tt.splat %arg3 : (i32) -> tensor<1x64xi32, #blocked2>
  %15 = arith.muli %6, %14 : tensor<1x64xi32, #blocked2>
  %16 = tt.broadcast %13 : (tensor<64x1x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked1>
  %17 = tt.broadcast %15 : (tensor<1x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %18 = triton_gpu.convert_layout %17 : (tensor<64x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked1>
  %19 = tt.addptr %16, %18 : tensor<64x64x!tt.ptr<f32>, #blocked1>, tensor<64x64xi32, #blocked1>
  %20 = triton_gpu.convert_layout %19 : (tensor<64x64x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked1>
  %21 = triton_gpu.convert_layout %11#0 : (tensor<64x64xf32, #blocked1>) -> tensor<64x64xf32, #blocked1>
  %22 = triton_gpu.convert_layout %cst : (tensor<64x64xi1, #blocked1>) -> tensor<64x64xi1, #blocked1>
  tt.store %20, %21, %22 : tensor<64x64xf32, #blocked1>
  tt.return
}
}

// CHECK-LABEL: loop_if
// CHECK-NOT: triton_gpu.convert_layout
//     CHECK: scf.for
// CHECK-NOT: triton_gpu.convert_layout
//     CHECK:   scf.if
// CHECK-NOT: triton_gpu.convert_layout
//     CHECK:     scf.yield
//     CHECK:   else
//     CHECK:     scf.yield
// CHECK-NOT: triton_gpu.convert_layout
//     CHECK:   scf.yield
//     CHECK: triton_gpu.convert_layout
// CHECK-NOT: triton_gpu.convert_layout
//     CHECK: tt.store
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func @loop_if(%arg0: !tt.ptr<f32>, %arg1: i32, %arg2: !tt.ptr<f32>, %arg3: i32, %arg4: i32) {
  %cst = arith.constant dense<true> : tensor<64x64xi1, #blocked1>
  %cst_0 = arith.constant dense<64> : tensor<64x64xi32, #blocked1>
  %c1 = arith.constant 1 : index
  %c32 = arith.constant 32 : index
  %c0 = arith.constant 0 : index
  %i0 = arith.constant 0 : i32
  %cst_1 = arith.constant dense<0.000000e+00> : tensor<64x64xf32, #blocked1>
  %00 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #slice1dim1>
  %01 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #slice2dim0>
  %1 = tt.expand_dims %00 {axis = 1 : i32} : (tensor<64xi32, #slice1dim1>) -> tensor<64x1xi32, #blocked1>
  %2 = tt.splat %arg1 : (i32) -> tensor<64x1xi32, #blocked1>
  %3 = arith.muli %1, %2 : tensor<64x1xi32, #blocked1>
  %4 = tt.splat %arg0 : (!tt.ptr<f32>) -> tensor<64x1x!tt.ptr<f32>, #blocked1>
  %5 = tt.addptr %4, %3 : tensor<64x1x!tt.ptr<f32>, #blocked1>, tensor<64x1xi32, #blocked1>
  %6 = tt.expand_dims %01 {axis = 0 : i32} : (tensor<64xi32, #slice2dim0>) -> tensor<1x64xi32, #blocked2>
  %7 = tt.broadcast %5 : (tensor<64x1x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked1>
  %8 = tt.broadcast %6 : (tensor<1x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %9 = triton_gpu.convert_layout %8 : (tensor<64x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked1>
  %10 = tt.addptr %7, %9 : tensor<64x64x!tt.ptr<f32>, #blocked1>, tensor<64x64xi32, #blocked1>
  %11:2 = scf.for %arg5 = %c0 to %c32 step %c1 iter_args(%arg6 = %cst_1, %arg7 = %10) -> (tensor<64x64xf32, #blocked1>, tensor<64x64x!tt.ptr<f32>, #blocked1>) {
    %33 = "triton_gpu.cmpi"(%i0, %i0) {predicate = 4 : i64} : (i32, i32) -> i1
    %34 = scf.if %33 -> (tensor<64x64xf32, #blocked1>) {
      %23 = triton_gpu.convert_layout %arg7 : (tensor<64x64x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked3>
      %24 = triton_gpu.convert_layout %cst : (tensor<64x64xi1, #blocked1>) -> tensor<64x64xi1, #blocked3>
      %25 = triton_gpu.convert_layout %cst_1 : (tensor<64x64xf32, #blocked1>) -> tensor<64x64xf32, #blocked3>
      %26 = tt.load %23, %24, %25 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<64x64xf32, #blocked3>
      %27 = triton_gpu.convert_layout %26 : (tensor<64x64xf32, #blocked3>) -> tensor<64x64xf32, #blocked1>
      scf.yield %27 : tensor<64x64xf32, #blocked1>
    } else {
      scf.yield %arg6 : tensor<64x64xf32, #blocked1>
    }
    %28 = arith.addf %arg6, %34 : tensor<64x64xf32, #blocked1>
    %29 = tt.addptr %arg7, %cst_0 : tensor<64x64x!tt.ptr<f32>, #blocked1>, tensor<64x64xi32, #blocked1>
    scf.yield %28, %29 : tensor<64x64xf32, #blocked1>, tensor<64x64x!tt.ptr<f32>, #blocked1>
  }
  %12 = tt.splat %arg2 : (!tt.ptr<f32>) -> tensor<64x1x!tt.ptr<f32>, #blocked1>
  %13 = tt.addptr %12, %1 : tensor<64x1x!tt.ptr<f32>, #blocked1>, tensor<64x1xi32, #blocked1>
  %14 = tt.splat %arg3 : (i32) -> tensor<1x64xi32, #blocked2>
  %15 = arith.muli %6, %14 : tensor<1x64xi32, #blocked2>
  %16 = tt.broadcast %13 : (tensor<64x1x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked1>
  %17 = tt.broadcast %15 : (tensor<1x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %18 = triton_gpu.convert_layout %17 : (tensor<64x64xi32, #blocked2>) -> tensor<64x64xi32, #blocked1>
  %19 = tt.addptr %16, %18 : tensor<64x64x!tt.ptr<f32>, #blocked1>, tensor<64x64xi32, #blocked1>
  %20 = triton_gpu.convert_layout %19 : (tensor<64x64x!tt.ptr<f32>, #blocked1>) -> tensor<64x64x!tt.ptr<f32>, #blocked1>
  %21 = triton_gpu.convert_layout %11#0 : (tensor<64x64xf32, #blocked1>) -> tensor<64x64xf32, #blocked1>
  %22 = triton_gpu.convert_layout %cst : (tensor<64x64xi1, #blocked1>) -> tensor<64x64xi1, #blocked1>
  tt.store %20, %21, %22 : tensor<64x64xf32, #blocked1>
  tt.return
}
}

// CHECK-LABEL: vecadd
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func @vecadd(%arg0: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg2: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg3: i32) {
  // CHECK-NOT: triton_gpu.convert_layout
  %c256_i32 = arith.constant 256 : i32
  %0 = tt.get_program_id x : i32
  %1 = arith.muli %0, %c256_i32 : i32
  %2 = tt.splat %1 : (i32) -> tensor<256xi32, #blocked5>
  %3 = tt.make_range {end = 256 : i32, start = 0 : i32} : tensor<256xi32, #blocked5>
  %4 = tt.splat %1 : (i32) -> tensor<256xi32, #blocked5>
  %5 = tt.make_range {end = 256 : i32, start = 0 : i32} : tensor<256xi32, #blocked5>
  %6 = tt.splat %1 : (i32) -> tensor<256xi32, #blocked5>
  %7 = tt.make_range {end = 256 : i32, start = 0 : i32} : tensor<256xi32, #blocked5>
  %8 = tt.splat %arg0 : (!tt.ptr<f32>) -> tensor<256x!tt.ptr<f32>, #blocked5>
  %9 = arith.addi %6, %7 : tensor<256xi32, #blocked5>
  %10 = tt.splat %arg1 : (!tt.ptr<f32>) -> tensor<256x!tt.ptr<f32>, #blocked5>
  %11 = arith.addi %4, %5 : tensor<256xi32, #blocked5>
  %12 = tt.addptr %8, %9 : tensor<256x!tt.ptr<f32>, #blocked5>, tensor<256xi32, #blocked5>
  %13 = tt.load %12 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<256xf32, #blocked5>
  %14 = triton_gpu.convert_layout %13 : (tensor<256xf32, #blocked5>) -> tensor<256xf32, #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [2], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>>
  %15 = tt.addptr %10, %11 : tensor<256x!tt.ptr<f32>, #blocked5>, tensor<256xi32, #blocked5>
  %16 = tt.load %15 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<256xf32, #blocked5>
  %17 = triton_gpu.convert_layout %16 : (tensor<256xf32, #blocked5>) -> tensor<256xf32, #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [2], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>>
  %18 = arith.addf %14, %17 : tensor<256xf32, #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [2], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>>
  %19 = tt.splat %arg2 : (!tt.ptr<f32>) -> tensor<256x!tt.ptr<f32>, #blocked5>
  %20 = arith.addi %2, %3 : tensor<256xi32, #blocked5>
  %21 = tt.addptr %19, %20 : tensor<256x!tt.ptr<f32>, #blocked5>, tensor<256xi32, #blocked5>
  %22 = triton_gpu.convert_layout %18 : (tensor<256xf32, #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [2], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>>) -> tensor<256xf32, #blocked5>
  tt.store %21, %22 : tensor<256xf32, #blocked5>
  tt.return
}
}

// Select has args with different element types
// CHECK-LABEL: select
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func @select(%arg0: !tt.ptr<f64> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f64> {tt.divisibility = 16 : i32}, %arg2: i32 {tt.divisibility = 16 : i32}) {
  // CHECK-NOT: triton_gpu.convert_layout
  %cst = arith.constant dense<30000> : tensor<1x1xi32, #blocked2>
  %cst_0 = arith.constant dense<30000> : tensor<1x512xi32, #blocked2>
  %c512 = arith.constant 512 : index
  %c30000 = arith.constant 30000 : index
  %c0 = arith.constant 0 : index
  %cst_1 = arith.constant dense<2048> : tensor<1x1xi32, #blocked2>
  %cst_2 = arith.constant dense<0.000000e+00> : tensor<1x512xf64, #blocked2>
  %0 = tt.get_program_id x : i32
  %1 = tt.make_range {end = 1 : i32, start = 0 : i32} : tensor<1xi32, #blocked0>
  %2 = triton_gpu.convert_layout %1 : (tensor<1xi32, #blocked0>) -> tensor<1xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>
  %3 = tt.expand_dims %2 {axis = 1 : i32} : (tensor<1xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>) -> tensor<1x1xi32, #blocked1>
  %4 = triton_gpu.convert_layout %3 : (tensor<1x1xi32, #blocked1>) -> tensor<1x1xi32, #blocked2>
  %5 = tt.splat %0 : (i32) -> tensor<1x1xi32, #blocked2>
  %6 = arith.addi %5, %4 : tensor<1x1xi32, #blocked2>
  %7 = "triton_gpu.cmpi"(%6, %cst_1) {predicate = 2 : i64} : (tensor<1x1xi32, #blocked2>, tensor<1x1xi32, #blocked2>) -> tensor<1x1xi1, #blocked2>
  %8 = tt.make_range {end = 512 : i32, start = 0 : i32} : tensor<512xi32, #blocked0>
  %9 = triton_gpu.convert_layout %8 : (tensor<512xi32, #blocked0>) -> tensor<512xi32, #triton_gpu.slice<{dim = 0, parent = #blocked2}>>
  %10 = tt.expand_dims %9 {axis = 0 : i32} : (tensor<512xi32, #triton_gpu.slice<{dim = 0, parent = #blocked2}>>) -> tensor<1x512xi32, #blocked2>
  %11 = arith.muli %6, %cst : tensor<1x1xi32, #blocked2>
  %12 = tt.broadcast %11 : (tensor<1x1xi32, #blocked2>) -> tensor<1x512xi32, #blocked2>
  %13 = tt.splat %arg0 : (!tt.ptr<f64>) -> tensor<1x512x!tt.ptr<f64>, #blocked2>
  %14 = tt.broadcast %7 : (tensor<1x1xi1, #blocked2>) -> tensor<1x512xi1, #blocked2>
  %15 = scf.for %arg3 = %c0 to %c30000 step %c512 iter_args(%arg4 = %cst_2) -> (tensor<1x512xf64, #blocked2>) {
    %16 = arith.index_cast %arg3 : index to i32
    %17 = tt.splat %16 : (i32) -> tensor<1x512xi32, #blocked2>
    %18 = arith.addi %17, %10 : tensor<1x512xi32, #blocked2>
    %19 = "triton_gpu.cmpi"(%18, %cst_0) {predicate = 2 : i64} : (tensor<1x512xi32, #blocked2>, tensor<1x512xi32, #blocked2>) -> tensor<1x512xi1, #blocked2>
    %20 = arith.addi %18, %12 : tensor<1x512xi32, #blocked2>
    %21 = tt.addptr %13, %20 : tensor<1x512x!tt.ptr<f64>, #blocked2>, tensor<1x512xi32, #blocked2>
    %22 = arith.andi %19, %14 : tensor<1x512xi1, #blocked2>
    %23 = triton_gpu.convert_layout %21 : (tensor<1x512x!tt.ptr<f64>, #blocked2>) -> tensor<1x512x!tt.ptr<f64>, #blocked3>
    %24 = triton_gpu.convert_layout %22 : (tensor<1x512xi1, #blocked2>) -> tensor<1x512xi1, #blocked3>
    %25 = tt.load %23, %24 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<1x512xf64, #blocked3>
    %26 = triton_gpu.convert_layout %25 : (tensor<1x512xf64, #blocked3>) -> tensor<1x512xf64, #blocked2>
    %27 = arith.andi %14, %19 : tensor<1x512xi1, #blocked2>
    %28 = "triton_gpu.cmpf"(%arg4, %26) {predicate = 4 : i64} : (tensor<1x512xf64, #blocked2>, tensor<1x512xf64, #blocked2>) -> tensor<1x512xi1, #blocked2>
    %29 = arith.andi %27, %28 : tensor<1x512xi1, #blocked2>
    %30 = "triton_gpu.select"(%29, %26, %arg4) : (tensor<1x512xi1, #blocked2>, tensor<1x512xf64, #blocked2>, tensor<1x512xf64, #blocked2>) -> tensor<1x512xf64, #blocked2>
    %31 = triton_gpu.convert_layout %21 : (tensor<1x512x!tt.ptr<f64>, #blocked2>) -> tensor<1x512x!tt.ptr<f64>, #blocked3>
    %32 = triton_gpu.convert_layout %30 : (tensor<1x512xf64, #blocked2>) -> tensor<1x512xf64, #blocked3>
    %33 = triton_gpu.convert_layout %27 : (tensor<1x512xi1, #blocked2>) -> tensor<1x512xi1, #blocked3>
    tt.store %31, %32, %33 : tensor<1x512xf64, #blocked3>
    scf.yield %30 : tensor<1x512xf64, #blocked2>
  }
  tt.return
}
}

// Make sure the following IR doesn't hang the compiler.
// CHECK-LABEL: long_func
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func public @long_func(%arg0: !tt.ptr<i64> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<i64> {tt.divisibility = 16 : i32}, %arg2: !tt.ptr<i64> {tt.divisibility = 16 : i32}, %arg3: !tt.ptr<i64> {tt.divisibility = 16 : i32}, %arg4: !tt.ptr<i64> {tt.divisibility = 16 : i32}, %arg5: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg6: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg7: !tt.ptr<i64> {tt.divisibility = 16 : i32}, %arg8: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg9: !tt.ptr<f64> {tt.divisibility = 16 : i32}, %arg10: !tt.ptr<f64> {tt.divisibility = 16 : i32}, %arg11: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg12: !tt.ptr<i32> {tt.divisibility = 16 : i32}, %arg13: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg14: !tt.ptr<f64> {tt.divisibility = 16 : i32}, %arg15: !tt.ptr<f64> {tt.divisibility = 16 : i32}, %arg16: i32 {tt.divisibility = 16 : i32}) {
  %cst = arith.constant dense<1.000000e+00> : tensor<1024xf32, #blocked0>
  %cst_0 = arith.constant dense<5.000000e-04> : tensor<1024xf32, #blocked0>
  %cst_1 = arith.constant dense<0.999499976> : tensor<1024xf32, #blocked0>
  %cst_2 = arith.constant dense<1.000000e+04> : tensor<1024xf32, #blocked0>
  %cst_3 = arith.constant dense<5000> : tensor<1024xi32, #blocked0>
  %cst_4 = arith.constant dense<150> : tensor<1024xi32, #blocked0>
  %cst_5 = arith.constant dense<false> : tensor<1024xi1, #blocked0>
  %cst_6 = arith.constant dense<2> : tensor<1024xi32, #blocked0>
  %cst_7 = arith.constant dense<4999> : tensor<1024xi32, #blocked0>
  %cst_8 = arith.constant dense<2499> : tensor<1024xi32, #blocked0>
  %cst_9 = arith.constant dense<2500> : tensor<1024xi32, #blocked0>
  %cst_10 = arith.constant dense<0.91629076> : tensor<1024xf32, #blocked0>
  %c2499_i32 = arith.constant 2499 : i32
  %cst_11 = arith.constant dense<1024> : tensor<1024xi32, #blocked0>
  %c1024_i32 = arith.constant 1024 : i32
  %cst_12 = arith.constant dense<1> : tensor<1024xi32, #blocked0>
  %cst_13 = arith.constant dense<0.000000e+00> : tensor<1024xf32, #blocked0>
  %cst_14 = arith.constant dense<0> : tensor<1024xi32, #blocked0>
  %0 = tt.get_program_id x : i32
  %1 = arith.muli %0, %c1024_i32 : i32
  %2 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, #blocked0>
  %3 = tt.splat %1 : (i32) -> tensor<1024xi32, #blocked0>
  %4 = arith.addi %3, %2 : tensor<1024xi32, #blocked0>
  %5 = "triton_gpu.cmpi"(%4, %cst_11) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %6 = tt.splat %arg5 : (!tt.ptr<f32>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %7 = tt.addptr %6, %4 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %8 = triton_gpu.convert_layout %7 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked1>
  %9 = triton_gpu.convert_layout %5 : (tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked1>
  %10 = tt.load %8, %9 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked1>
  %11 = triton_gpu.convert_layout %10 : (tensor<1024xf32, #blocked1>) -> tensor<1024xf32, #blocked0>
  %12 = tt.splat %arg7 : (!tt.ptr<i64>) -> tensor<1024x!tt.ptr<i64>, #blocked0>
  %13 = tt.addptr %12, %4 : tensor<1024x!tt.ptr<i64>, #blocked0>, tensor<1024xi32, #blocked0>
  %14 = triton_gpu.convert_layout %13 : (tensor<1024x!tt.ptr<i64>, #blocked0>) -> tensor<1024x!tt.ptr<i64>, #blocked2>
  %15 = triton_gpu.convert_layout %5 : (tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked2>
  %16 = tt.load %14, %15 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xi64, #blocked2>
  %17 = triton_gpu.convert_layout %16 : (tensor<1024xi64, #blocked2>) -> tensor<1024xi64, #blocked0>
  %18 = tt.splat %arg8 : (!tt.ptr<f32>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %19 = tt.addptr %18, %4 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %20 = triton_gpu.convert_layout %19 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked1>
  %21 = triton_gpu.convert_layout %5 : (tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked1>
  %22 = tt.load %20, %21 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked1>
  %23 = triton_gpu.convert_layout %22 : (tensor<1024xf32, #blocked1>) -> tensor<1024xf32, #blocked0>
  %24 = arith.subf %cst_13, %11 : tensor<1024xf32, #blocked0>
  %25 = math.exp %24 : tensor<1024xf32, #blocked0>
  %26 = arith.sitofp %cst_12 : tensor<1024xi32, #blocked0> to tensor<1024xf32, #blocked0>
  %27 = arith.addf %25, %26 : tensor<1024xf32, #blocked0>
  %28 = arith.divf %26, %27 : tensor<1024xf32, #blocked0>
  %29 = tt.addptr %arg6, %c2499_i32 : !tt.ptr<f32>, i32
  %30 = tt.load %29 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : f32
  %31 = arith.subf %11, %cst_10 : tensor<1024xf32, #blocked0>
  %32 = arith.subf %cst_13, %31 : tensor<1024xf32, #blocked0>
  %33 = math.exp %32 : tensor<1024xf32, #blocked0>
  %34 = arith.addf %33, %26 : tensor<1024xf32, #blocked0>
  %35 = arith.divf %26, %34 : tensor<1024xf32, #blocked0>
  %36 = tt.splat %30 : (f32) -> tensor<1024xf32, #blocked0>
  %37 = "triton_gpu.cmpf"(%36, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %38 = "triton_gpu.select"(%37, %cst_14, %cst_9) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %39 = "triton_gpu.select"(%37, %cst_8, %cst_7) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %40 = arith.subi %39, %38 : tensor<1024xi32, #blocked0>
  %41 = "triton_gpu.cmpi"(%40, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %42 = "triton_gpu.cmpi"(%41, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %43 = arith.remsi %40, %cst_6 : tensor<1024xi32, #blocked0>
  %44 = "triton_gpu.cmpi"(%43, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %45 = arith.divsi %40, %cst_6 : tensor<1024xi32, #blocked0>
  %46 = arith.subi %45, %cst_12 : tensor<1024xi32, #blocked0>
  %47 = "triton_gpu.select"(%44, %46, %45) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %48 = "triton_gpu.select"(%42, %47, %45) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %49 = arith.addi %38, %48 : tensor<1024xi32, #blocked0>
  %50 = "triton_gpu.cmpi"(%38, %39) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %51 = "triton_gpu.select"(%50, %49, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %52 = tt.splat %arg6 : (!tt.ptr<f32>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %53 = tt.addptr %52, %51 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %54 = triton_gpu.convert_layout %53 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %55 = tt.load %54 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %56 = "triton_gpu.cmpf"(%55, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %57 = "triton_gpu.cmpi"(%56, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %58 = arith.andi %57, %50 : tensor<1024xi1, #blocked0>
  %59 = arith.addi %51, %cst_12 : tensor<1024xi32, #blocked0>
  %60 = "triton_gpu.select"(%58, %59, %38) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %61 = arith.andi %56, %50 : tensor<1024xi1, #blocked0>
  %62 = "triton_gpu.select"(%61, %51, %39) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %63 = "triton_gpu.cmpi"(%60, %62) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %64 = arith.subi %62, %60 : tensor<1024xi32, #blocked0>
  %65 = "triton_gpu.cmpi"(%64, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %66 = "triton_gpu.cmpi"(%65, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %67 = arith.remsi %64, %cst_6 : tensor<1024xi32, #blocked0>
  %68 = "triton_gpu.cmpi"(%67, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %69 = arith.divsi %64, %cst_6 : tensor<1024xi32, #blocked0>
  %70 = arith.subi %69, %cst_12 : tensor<1024xi32, #blocked0>
  %71 = "triton_gpu.select"(%68, %70, %69) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %72 = "triton_gpu.select"(%66, %71, %69) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %73 = arith.addi %60, %72 : tensor<1024xi32, #blocked0>
  %74 = "triton_gpu.select"(%63, %73, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %75 = tt.addptr %52, %74 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %76 = triton_gpu.convert_layout %75 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %77 = tt.load %76 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %78 = "triton_gpu.cmpf"(%77, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %79 = "triton_gpu.cmpi"(%78, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %80 = arith.andi %79, %63 : tensor<1024xi1, #blocked0>
  %81 = arith.addi %74, %cst_12 : tensor<1024xi32, #blocked0>
  %82 = "triton_gpu.select"(%80, %81, %60) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %83 = arith.andi %78, %63 : tensor<1024xi1, #blocked0>
  %84 = "triton_gpu.select"(%83, %74, %62) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %85 = "triton_gpu.cmpi"(%82, %84) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %86 = arith.subi %84, %82 : tensor<1024xi32, #blocked0>
  %87 = "triton_gpu.cmpi"(%86, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %88 = "triton_gpu.cmpi"(%87, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %89 = arith.remsi %86, %cst_6 : tensor<1024xi32, #blocked0>
  %90 = "triton_gpu.cmpi"(%89, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %91 = arith.divsi %86, %cst_6 : tensor<1024xi32, #blocked0>
  %92 = arith.subi %91, %cst_12 : tensor<1024xi32, #blocked0>
  %93 = "triton_gpu.select"(%90, %92, %91) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %94 = "triton_gpu.select"(%88, %93, %91) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %95 = arith.addi %82, %94 : tensor<1024xi32, #blocked0>
  %96 = "triton_gpu.select"(%85, %95, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %97 = tt.addptr %52, %96 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %98 = triton_gpu.convert_layout %97 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %99 = tt.load %98 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %100 = "triton_gpu.cmpf"(%99, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %101 = "triton_gpu.cmpi"(%100, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %102 = arith.andi %101, %85 : tensor<1024xi1, #blocked0>
  %103 = arith.addi %96, %cst_12 : tensor<1024xi32, #blocked0>
  %104 = "triton_gpu.select"(%102, %103, %82) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %105 = arith.andi %100, %85 : tensor<1024xi1, #blocked0>
  %106 = "triton_gpu.select"(%105, %96, %84) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %107 = "triton_gpu.cmpi"(%104, %106) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %108 = arith.subi %106, %104 : tensor<1024xi32, #blocked0>
  %109 = "triton_gpu.cmpi"(%108, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %110 = "triton_gpu.cmpi"(%109, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %111 = arith.remsi %108, %cst_6 : tensor<1024xi32, #blocked0>
  %112 = "triton_gpu.cmpi"(%111, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %113 = arith.divsi %108, %cst_6 : tensor<1024xi32, #blocked0>
  %114 = arith.subi %113, %cst_12 : tensor<1024xi32, #blocked0>
  %115 = "triton_gpu.select"(%112, %114, %113) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %116 = "triton_gpu.select"(%110, %115, %113) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %117 = arith.addi %104, %116 : tensor<1024xi32, #blocked0>
  %118 = "triton_gpu.select"(%107, %117, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %119 = tt.addptr %52, %118 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %120 = triton_gpu.convert_layout %119 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %121 = tt.load %120 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %122 = "triton_gpu.cmpf"(%121, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %123 = "triton_gpu.cmpi"(%122, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %124 = arith.andi %123, %107 : tensor<1024xi1, #blocked0>
  %125 = arith.addi %118, %cst_12 : tensor<1024xi32, #blocked0>
  %126 = "triton_gpu.select"(%124, %125, %104) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %127 = arith.andi %122, %107 : tensor<1024xi1, #blocked0>
  %128 = "triton_gpu.select"(%127, %118, %106) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %129 = "triton_gpu.cmpi"(%126, %128) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %130 = arith.subi %128, %126 : tensor<1024xi32, #blocked0>
  %131 = "triton_gpu.cmpi"(%130, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %132 = "triton_gpu.cmpi"(%131, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %133 = arith.remsi %130, %cst_6 : tensor<1024xi32, #blocked0>
  %134 = "triton_gpu.cmpi"(%133, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %135 = arith.divsi %130, %cst_6 : tensor<1024xi32, #blocked0>
  %136 = arith.subi %135, %cst_12 : tensor<1024xi32, #blocked0>
  %137 = "triton_gpu.select"(%134, %136, %135) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %138 = "triton_gpu.select"(%132, %137, %135) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %139 = arith.addi %126, %138 : tensor<1024xi32, #blocked0>
  %140 = "triton_gpu.select"(%129, %139, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %141 = tt.addptr %52, %140 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %142 = triton_gpu.convert_layout %141 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %143 = tt.load %142 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %144 = "triton_gpu.cmpf"(%143, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %145 = "triton_gpu.cmpi"(%144, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %146 = arith.andi %145, %129 : tensor<1024xi1, #blocked0>
  %147 = arith.addi %140, %cst_12 : tensor<1024xi32, #blocked0>
  %148 = "triton_gpu.select"(%146, %147, %126) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %149 = arith.andi %144, %129 : tensor<1024xi1, #blocked0>
  %150 = "triton_gpu.select"(%149, %140, %128) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %151 = "triton_gpu.cmpi"(%148, %150) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %152 = arith.subi %150, %148 : tensor<1024xi32, #blocked0>
  %153 = "triton_gpu.cmpi"(%152, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %154 = "triton_gpu.cmpi"(%153, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %155 = arith.remsi %152, %cst_6 : tensor<1024xi32, #blocked0>
  %156 = "triton_gpu.cmpi"(%155, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %157 = arith.divsi %152, %cst_6 : tensor<1024xi32, #blocked0>
  %158 = arith.subi %157, %cst_12 : tensor<1024xi32, #blocked0>
  %159 = "triton_gpu.select"(%156, %158, %157) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %160 = "triton_gpu.select"(%154, %159, %157) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %161 = arith.addi %148, %160 : tensor<1024xi32, #blocked0>
  %162 = "triton_gpu.select"(%151, %161, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %163 = tt.addptr %52, %162 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %164 = triton_gpu.convert_layout %163 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %165 = tt.load %164 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %166 = "triton_gpu.cmpf"(%165, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %167 = "triton_gpu.cmpi"(%166, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %168 = arith.andi %167, %151 : tensor<1024xi1, #blocked0>
  %169 = arith.addi %162, %cst_12 : tensor<1024xi32, #blocked0>
  %170 = "triton_gpu.select"(%168, %169, %148) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %171 = arith.andi %166, %151 : tensor<1024xi1, #blocked0>
  %172 = "triton_gpu.select"(%171, %162, %150) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %173 = "triton_gpu.cmpi"(%170, %172) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %174 = arith.subi %172, %170 : tensor<1024xi32, #blocked0>
  %175 = "triton_gpu.cmpi"(%174, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %176 = "triton_gpu.cmpi"(%175, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %177 = arith.remsi %174, %cst_6 : tensor<1024xi32, #blocked0>
  %178 = "triton_gpu.cmpi"(%177, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %179 = arith.divsi %174, %cst_6 : tensor<1024xi32, #blocked0>
  %180 = arith.subi %179, %cst_12 : tensor<1024xi32, #blocked0>
  %181 = "triton_gpu.select"(%178, %180, %179) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %182 = "triton_gpu.select"(%176, %181, %179) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %183 = arith.addi %170, %182 : tensor<1024xi32, #blocked0>
  %184 = "triton_gpu.select"(%173, %183, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %185 = tt.addptr %52, %184 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %186 = triton_gpu.convert_layout %185 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %187 = tt.load %186 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %188 = "triton_gpu.cmpf"(%187, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %189 = "triton_gpu.cmpi"(%188, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %190 = arith.andi %189, %173 : tensor<1024xi1, #blocked0>
  %191 = arith.addi %184, %cst_12 : tensor<1024xi32, #blocked0>
  %192 = "triton_gpu.select"(%190, %191, %170) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %193 = arith.andi %188, %173 : tensor<1024xi1, #blocked0>
  %194 = "triton_gpu.select"(%193, %184, %172) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %195 = "triton_gpu.cmpi"(%192, %194) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %196 = arith.subi %194, %192 : tensor<1024xi32, #blocked0>
  %197 = "triton_gpu.cmpi"(%196, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %198 = "triton_gpu.cmpi"(%197, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %199 = arith.remsi %196, %cst_6 : tensor<1024xi32, #blocked0>
  %200 = "triton_gpu.cmpi"(%199, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %201 = arith.divsi %196, %cst_6 : tensor<1024xi32, #blocked0>
  %202 = arith.subi %201, %cst_12 : tensor<1024xi32, #blocked0>
  %203 = "triton_gpu.select"(%200, %202, %201) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %204 = "triton_gpu.select"(%198, %203, %201) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %205 = arith.addi %192, %204 : tensor<1024xi32, #blocked0>
  %206 = "triton_gpu.select"(%195, %205, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %207 = tt.addptr %52, %206 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %208 = triton_gpu.convert_layout %207 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %209 = tt.load %208 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %210 = "triton_gpu.cmpf"(%209, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %211 = "triton_gpu.cmpi"(%210, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %212 = arith.andi %211, %195 : tensor<1024xi1, #blocked0>
  %213 = arith.addi %206, %cst_12 : tensor<1024xi32, #blocked0>
  %214 = "triton_gpu.select"(%212, %213, %192) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %215 = arith.andi %210, %195 : tensor<1024xi1, #blocked0>
  %216 = "triton_gpu.select"(%215, %206, %194) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %217 = "triton_gpu.cmpi"(%214, %216) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %218 = arith.subi %216, %214 : tensor<1024xi32, #blocked0>
  %219 = "triton_gpu.cmpi"(%218, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %220 = "triton_gpu.cmpi"(%219, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %221 = arith.remsi %218, %cst_6 : tensor<1024xi32, #blocked0>
  %222 = "triton_gpu.cmpi"(%221, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %223 = arith.divsi %218, %cst_6 : tensor<1024xi32, #blocked0>
  %224 = arith.subi %223, %cst_12 : tensor<1024xi32, #blocked0>
  %225 = "triton_gpu.select"(%222, %224, %223) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %226 = "triton_gpu.select"(%220, %225, %223) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %227 = arith.addi %214, %226 : tensor<1024xi32, #blocked0>
  %228 = "triton_gpu.select"(%217, %227, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %229 = tt.addptr %52, %228 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %230 = triton_gpu.convert_layout %229 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %231 = tt.load %230 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %232 = "triton_gpu.cmpf"(%231, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %233 = "triton_gpu.cmpi"(%232, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %234 = arith.andi %233, %217 : tensor<1024xi1, #blocked0>
  %235 = arith.addi %228, %cst_12 : tensor<1024xi32, #blocked0>
  %236 = "triton_gpu.select"(%234, %235, %214) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %237 = arith.andi %232, %217 : tensor<1024xi1, #blocked0>
  %238 = "triton_gpu.select"(%237, %228, %216) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %239 = "triton_gpu.cmpi"(%236, %238) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %240 = arith.subi %238, %236 : tensor<1024xi32, #blocked0>
  %241 = "triton_gpu.cmpi"(%240, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %242 = "triton_gpu.cmpi"(%241, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %243 = arith.remsi %240, %cst_6 : tensor<1024xi32, #blocked0>
  %244 = "triton_gpu.cmpi"(%243, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %245 = arith.divsi %240, %cst_6 : tensor<1024xi32, #blocked0>
  %246 = arith.subi %245, %cst_12 : tensor<1024xi32, #blocked0>
  %247 = "triton_gpu.select"(%244, %246, %245) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %248 = "triton_gpu.select"(%242, %247, %245) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %249 = arith.addi %236, %248 : tensor<1024xi32, #blocked0>
  %250 = "triton_gpu.select"(%239, %249, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %251 = tt.addptr %52, %250 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %252 = triton_gpu.convert_layout %251 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %253 = tt.load %252 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %254 = "triton_gpu.cmpf"(%253, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %255 = "triton_gpu.cmpi"(%254, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %256 = arith.andi %255, %239 : tensor<1024xi1, #blocked0>
  %257 = arith.addi %250, %cst_12 : tensor<1024xi32, #blocked0>
  %258 = "triton_gpu.select"(%256, %257, %236) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %259 = arith.andi %254, %239 : tensor<1024xi1, #blocked0>
  %260 = "triton_gpu.select"(%259, %250, %238) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %261 = "triton_gpu.cmpi"(%258, %260) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %262 = arith.subi %260, %258 : tensor<1024xi32, #blocked0>
  %263 = "triton_gpu.cmpi"(%262, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %264 = "triton_gpu.cmpi"(%263, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %265 = arith.remsi %262, %cst_6 : tensor<1024xi32, #blocked0>
  %266 = "triton_gpu.cmpi"(%265, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %267 = arith.divsi %262, %cst_6 : tensor<1024xi32, #blocked0>
  %268 = arith.subi %267, %cst_12 : tensor<1024xi32, #blocked0>
  %269 = "triton_gpu.select"(%266, %268, %267) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %270 = "triton_gpu.select"(%264, %269, %267) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %271 = arith.addi %258, %270 : tensor<1024xi32, #blocked0>
  %272 = "triton_gpu.select"(%261, %271, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %273 = tt.addptr %52, %272 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %274 = triton_gpu.convert_layout %273 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %275 = tt.load %274 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %276 = "triton_gpu.cmpf"(%275, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %277 = "triton_gpu.cmpi"(%276, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %278 = arith.andi %277, %261 : tensor<1024xi1, #blocked0>
  %279 = arith.addi %272, %cst_12 : tensor<1024xi32, #blocked0>
  %280 = "triton_gpu.select"(%278, %279, %258) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %281 = arith.andi %276, %261 : tensor<1024xi1, #blocked0>
  %282 = "triton_gpu.select"(%281, %272, %260) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %283 = "triton_gpu.cmpi"(%280, %282) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %284 = arith.subi %282, %280 : tensor<1024xi32, #blocked0>
  %285 = "triton_gpu.cmpi"(%284, %cst_14) {predicate = 2 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %286 = "triton_gpu.cmpi"(%285, %cst_5) {predicate = 1 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %287 = arith.remsi %284, %cst_6 : tensor<1024xi32, #blocked0>
  %288 = "triton_gpu.cmpi"(%287, %cst_14) {predicate = 1 : i64} : (tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %289 = arith.divsi %284, %cst_6 : tensor<1024xi32, #blocked0>
  %290 = arith.subi %289, %cst_12 : tensor<1024xi32, #blocked0>
  %291 = "triton_gpu.select"(%288, %290, %289) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %292 = "triton_gpu.select"(%286, %291, %289) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %293 = arith.addi %280, %292 : tensor<1024xi32, #blocked0>
  %294 = "triton_gpu.select"(%283, %293, %cst_14) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %295 = tt.addptr %52, %294 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %296 = triton_gpu.convert_layout %295 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %297 = tt.load %296 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked0>
  %298 = "triton_gpu.cmpf"(%297, %35) {predicate = 3 : i64} : (tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xi1, #blocked0>
  %299 = "triton_gpu.cmpi"(%298, %cst_5) {predicate = 0 : i64} : (tensor<1024xi1, #blocked0>, tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked0>
  %300 = arith.andi %299, %283 : tensor<1024xi1, #blocked0>
  %301 = arith.addi %294, %cst_12 : tensor<1024xi32, #blocked0>
  %302 = "triton_gpu.select"(%300, %301, %280) : (tensor<1024xi1, #blocked0>, tensor<1024xi32, #blocked0>, tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked0>
  %303 = arith.extsi %cst_12 : tensor<1024xi32, #blocked0> to tensor<1024xi64, #blocked0>
  %304 = "triton_gpu.cmpi"(%17, %303) {predicate = 0 : i64} : (tensor<1024xi64, #blocked0>, tensor<1024xi64, #blocked0>) -> tensor<1024xi1, #blocked0>
  %305 = arith.fptosi %23 : tensor<1024xf32, #blocked0> to tensor<1024xi64, #blocked0>
  %306 = arith.extsi %cst_14 : tensor<1024xi32, #blocked0> to tensor<1024xi64, #blocked0>
  %307 = "triton_gpu.cmpi"(%306, %305) {predicate = 4 : i64} : (tensor<1024xi64, #blocked0>, tensor<1024xi64, #blocked0>) -> tensor<1024xi1, #blocked0>
  %308 = arith.extsi %cst_4 : tensor<1024xi32, #blocked0> to tensor<1024xi64, #blocked0>
  %309 = "triton_gpu.cmpi"(%305, %308) {predicate = 4 : i64} : (tensor<1024xi64, #blocked0>, tensor<1024xi64, #blocked0>) -> tensor<1024xi1, #blocked0>
  %310 = "triton_gpu.select"(%309, %306, %305) : (tensor<1024xi1, #blocked0>, tensor<1024xi64, #blocked0>, tensor<1024xi64, #blocked0>) -> tensor<1024xi64, #blocked0>
  %311 = "triton_gpu.select"(%307, %306, %310) : (tensor<1024xi1, #blocked0>, tensor<1024xi64, #blocked0>, tensor<1024xi64, #blocked0>) -> tensor<1024xi64, #blocked0>
  %312 = "triton_gpu.select"(%304, %311, %306) : (tensor<1024xi1, #blocked0>, tensor<1024xi64, #blocked0>, tensor<1024xi64, #blocked0>) -> tensor<1024xi64, #blocked0>
  %313 = arith.extsi %cst_3 : tensor<1024xi32, #blocked0> to tensor<1024xi64, #blocked0>
  %314 = arith.muli %312, %313 : tensor<1024xi64, #blocked0>
  %315 = arith.extsi %302 : tensor<1024xi32, #blocked0> to tensor<1024xi64, #blocked0>
  %316 = arith.addi %315, %314 : tensor<1024xi64, #blocked0>
  %317 = arith.trunci %316 : tensor<1024xi64, #blocked0> to tensor<1024xi32, #blocked0>
  %318 = arith.extsi %317 : tensor<1024xi32, #blocked0> to tensor<1024xi64, #blocked0>
  %319 = tt.splat %arg9 : (!tt.ptr<f64>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %320 = tt.addptr %319, %318 : tensor<1024x!tt.ptr<f64>, #blocked0>, tensor<1024xi64, #blocked0>
  %321 = triton_gpu.convert_layout %320 : (tensor<1024x!tt.ptr<f64>, #blocked0>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %322 = tt.load %321 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf64, #blocked0>
  %323 = arith.extf %cst_2 : tensor<1024xf32, #blocked0> to tensor<1024xf64, #blocked0>
  %324 = "triton_gpu.cmpf"(%322, %323) {predicate = 2 : i64} : (tensor<1024xf64, #blocked0>, tensor<1024xf64, #blocked0>) -> tensor<1024xi1, #blocked0>
  %325 = tt.splat %arg10 : (!tt.ptr<f64>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %326 = tt.addptr %325, %318 : tensor<1024x!tt.ptr<f64>, #blocked0>, tensor<1024xi64, #blocked0>
  %327 = triton_gpu.convert_layout %326 : (tensor<1024x!tt.ptr<f64>, #blocked0>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %328 = tt.load %327 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf64, #blocked0>
  %329 = arith.divf %328, %322 : tensor<1024xf64, #blocked0>
  %330 = arith.truncf %329 : tensor<1024xf64, #blocked0> to tensor<1024xf32, #blocked0>
  %331 = arith.mulf %330, %cst_1 : tensor<1024xf32, #blocked0>
  %332 = arith.mulf %35, %cst_0 : tensor<1024xf32, #blocked0>
  %333 = arith.addf %331, %332 : tensor<1024xf32, #blocked0>
  %334 = "triton_gpu.select"(%324, %333, %35) : (tensor<1024xi1, #blocked0>, tensor<1024xf32, #blocked0>, tensor<1024xf32, #blocked0>) -> tensor<1024xf32, #blocked0>
  %335 = tt.addptr %319, %317 : tensor<1024x!tt.ptr<f64>, #blocked0>, tensor<1024xi32, #blocked0>
  %336 = triton_gpu.convert_layout %335 : (tensor<1024x!tt.ptr<f64>, #blocked0>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %337 = tt.load %336 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf64, #blocked0>
  %338 = arith.extf %cst : tensor<1024xf32, #blocked0> to tensor<1024xf64, #blocked0>
  %339 = arith.mulf %337, %338 : tensor<1024xf64, #blocked0>
  %340 = tt.addptr %325, %317 : tensor<1024x!tt.ptr<f64>, #blocked0>, tensor<1024xi32, #blocked0>
  %341 = triton_gpu.convert_layout %340 : (tensor<1024x!tt.ptr<f64>, #blocked0>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %342 = tt.load %341 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf64, #blocked0>
  %343 = arith.mulf %342, %338 : tensor<1024xf64, #blocked0>
  %344 = tt.splat %arg11 : (!tt.ptr<f32>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %345 = tt.addptr %344, %4 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %346 = triton_gpu.convert_layout %345 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked1>
  %347 = triton_gpu.convert_layout %28 : (tensor<1024xf32, #blocked0>) -> tensor<1024xf32, #blocked1>
  %348 = triton_gpu.convert_layout %5 : (tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked1>
  tt.store %346, %347, %348 : tensor<1024xf32, #blocked1>
  %349 = tt.splat %arg12 : (!tt.ptr<i32>) -> tensor<1024x!tt.ptr<i32>, #blocked0>
  %350 = tt.addptr %349, %4 : tensor<1024x!tt.ptr<i32>, #blocked0>, tensor<1024xi32, #blocked0>
  %351 = triton_gpu.convert_layout %350 : (tensor<1024x!tt.ptr<i32>, #blocked0>) -> tensor<1024x!tt.ptr<i32>, #blocked1>
  %352 = triton_gpu.convert_layout %317 : (tensor<1024xi32, #blocked0>) -> tensor<1024xi32, #blocked1>
  %353 = triton_gpu.convert_layout %5 : (tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked1>
  tt.store %351, %352, %353 : tensor<1024xi32, #blocked1>
  %354 = tt.splat %arg13 : (!tt.ptr<f32>) -> tensor<1024x!tt.ptr<f32>, #blocked0>
  %355 = tt.addptr %354, %4 : tensor<1024x!tt.ptr<f32>, #blocked0>, tensor<1024xi32, #blocked0>
  %356 = triton_gpu.convert_layout %355 : (tensor<1024x!tt.ptr<f32>, #blocked0>) -> tensor<1024x!tt.ptr<f32>, #blocked1>
  %357 = triton_gpu.convert_layout %334 : (tensor<1024xf32, #blocked0>) -> tensor<1024xf32, #blocked1>
  %358 = triton_gpu.convert_layout %5 : (tensor<1024xi1, #blocked0>) -> tensor<1024xi1, #blocked1>
  tt.store %356, %357, %358 : tensor<1024xf32, #blocked1>
  %359 = tt.splat %arg14 : (!tt.ptr<f64>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %360 = tt.addptr %359, %318 : tensor<1024x!tt.ptr<f64>, #blocked0>, tensor<1024xi64, #blocked0>
  %361 = triton_gpu.convert_layout %360 : (tensor<1024x!tt.ptr<f64>, #blocked0>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %362 = triton_gpu.convert_layout %339 : (tensor<1024xf64, #blocked0>) -> tensor<1024xf64, #blocked0>
  tt.store %361, %362 : tensor<1024xf64, #blocked0>
  %363 = tt.splat %arg15 : (!tt.ptr<f64>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %364 = tt.addptr %363, %318 : tensor<1024x!tt.ptr<f64>, #blocked0>, tensor<1024xi64, #blocked0>
  %365 = triton_gpu.convert_layout %364 : (tensor<1024x!tt.ptr<f64>, #blocked0>) -> tensor<1024x!tt.ptr<f64>, #blocked0>
  %366 = triton_gpu.convert_layout %343 : (tensor<1024xf64, #blocked0>) -> tensor<1024xf64, #blocked0>
  tt.store %365, %366 : tensor<1024xf64, #blocked0>
  tt.return
}
}

// A mnist model from torch inductor.
// Check if topological sort is working correct and there's no unnecessary convert
// CHECK-LABEL: mnist
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func public @mnist(%arg0: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg2: i32 {tt.divisibility = 16 : i32}, %arg3: i32) {
  // CHECK-NOT: triton_gpu.convert_layout
  %cst = arith.constant dense<10> : tensor<16x1xi32, #blocked2>
  %cst_0 = arith.constant dense<10> : tensor<1x16xi32, #blocked3>
  %c16_i32 = arith.constant 16 : i32
  %cst_1 = arith.constant dense<64> : tensor<16x1xi32, #blocked2>
  %cst_2 = arith.constant dense<0xFF800000> : tensor<16x16xf32, #blocked2>
  %cst_3 = arith.constant dense<0.000000e+00> : tensor<16x16xf32, #blocked2>
  %cst_4 = arith.constant dense<0> : tensor<16x16xi32, #blocked2>
  %0 = tt.get_program_id x : i32
  %1 = arith.muli %0, %c16_i32 : i32
  %2 = tt.make_range {end = 16 : i32, start = 0 : i32} : tensor<16xi32, #blocked0>
  %3 = triton_gpu.convert_layout %2 : (tensor<16xi32, #blocked0>) -> tensor<16xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>
  %4 = tt.expand_dims %3 {axis = 1 : i32} : (tensor<16xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>) -> tensor<16x1xi32, #blocked1>
  %5 = triton_gpu.convert_layout %4 : (tensor<16x1xi32, #blocked1>) -> tensor<16x1xi32, #blocked2>
  %6 = tt.splat %1 : (i32) -> tensor<16x1xi32, #blocked2>
  %7 = arith.addi %6, %5 : tensor<16x1xi32, #blocked2>
  %8 = "triton_gpu.cmpi"(%7, %cst_1) {predicate = 2 : i64} : (tensor<16x1xi32, #blocked2>, tensor<16x1xi32, #blocked2>) -> tensor<16x1xi1, #blocked2>
  %9 = triton_gpu.convert_layout %2 : (tensor<16xi32, #blocked0>) -> tensor<16xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>
  %10 = tt.expand_dims %9 {axis = 0 : i32} : (tensor<16xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>) -> tensor<1x16xi32, #blocked3>
  %11 = "triton_gpu.cmpi"(%10, %cst_0) {predicate = 2 : i64} : (tensor<1x16xi32, #blocked3>, tensor<1x16xi32, #blocked3>) -> tensor<1x16xi1, #blocked3>
  %12 = arith.muli %7, %cst : tensor<16x1xi32, #blocked2>
  %13 = tt.broadcast %10 : (tensor<1x16xi32, #blocked3>) -> tensor<16x16xi32, #blocked3>
  %14 = triton_gpu.convert_layout %13 : (tensor<16x16xi32, #blocked3>) -> tensor<16x16xi32, #blocked2>
  %15 = tt.broadcast %12 : (tensor<16x1xi32, #blocked2>) -> tensor<16x16xi32, #blocked2>
  %16 = arith.addi %14, %15 : tensor<16x16xi32, #blocked2>
  %17 = tt.splat %arg0 : (!tt.ptr<f32>) -> tensor<16x16x!tt.ptr<f32>, #blocked2>
  %18 = tt.addptr %17, %16 : tensor<16x16x!tt.ptr<f32>, #blocked2>, tensor<16x16xi32, #blocked2>
  %19 = tt.broadcast %11 : (tensor<1x16xi1, #blocked3>) -> tensor<16x16xi1, #blocked3>
  %20 = triton_gpu.convert_layout %19 : (tensor<16x16xi1, #blocked3>) -> tensor<16x16xi1, #blocked2>
  %21 = tt.broadcast %8 : (tensor<16x1xi1, #blocked2>) -> tensor<16x16xi1, #blocked2>
  %22 = arith.andi %20, %21 : tensor<16x16xi1, #blocked2>
  %23 = triton_gpu.convert_layout %18 : (tensor<16x16x!tt.ptr<f32>, #blocked2>) -> tensor<16x16x!tt.ptr<f32>, #blocked4>
  %24 = triton_gpu.convert_layout %22 : (tensor<16x16xi1, #blocked2>) -> tensor<16x16xi1, #blocked4>
  %25 = tt.load %23, %24 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<16x16xf32, #blocked4>
  %26 = triton_gpu.convert_layout %25 : (tensor<16x16xf32, #blocked4>) -> tensor<16x16xf32, #blocked2>
  %27 = "triton_gpu.cmpf"(%cst_2, %26) {predicate = 4 : i64} : (tensor<16x16xf32, #blocked2>, tensor<16x16xf32, #blocked2>) -> tensor<16x16xi1, #blocked2>
  %28 = arith.andi %22, %27 : tensor<16x16xi1, #blocked2>
  %29 = "triton_gpu.select"(%28, %26, %cst_2) : (tensor<16x16xi1, #blocked2>, tensor<16x16xf32, #blocked2>, tensor<16x16xf32, #blocked2>) -> tensor<16x16xf32, #blocked2>
  %30 = "tt.reduce" (%29) ({
  ^bb0(%arg4: f32, %arg5: f32):
    %max = arith.maximumf %arg4, %arg5 : f32
    tt.reduce.return %max : f32
  }) {axis = 1 : i32} : (tensor<16x16xf32, #blocked2>) -> tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
  %31 = triton_gpu.convert_layout %30 : (tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<16xf32, #blocked0>
  %32 = triton_gpu.convert_layout %31 : (tensor<16xf32, #blocked0>) -> tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>
  %33 = tt.expand_dims %32 {axis = 1 : i32} : (tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>) -> tensor<16x1xf32, #blocked1>
  %34 = triton_gpu.convert_layout %33 : (tensor<16x1xf32, #blocked1>) -> tensor<16x1xf32, #blocked2>
  %35 = arith.sitofp %cst_4 : tensor<16x16xi32, #blocked2> to tensor<16x16xf32, #blocked2>
  %36 = arith.addf %35, %cst_3 : tensor<16x16xf32, #blocked2>
  %37 = triton_gpu.convert_layout %18 : (tensor<16x16x!tt.ptr<f32>, #blocked2>) -> tensor<16x16x!tt.ptr<f32>, #blocked4>
  %38 = triton_gpu.convert_layout %22 : (tensor<16x16xi1, #blocked2>) -> tensor<16x16xi1, #blocked4>
  %39 = tt.load %37, %38 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<16x16xf32, #blocked4>
  %40 = triton_gpu.convert_layout %39 : (tensor<16x16xf32, #blocked4>) -> tensor<16x16xf32, #blocked2>
  %41 = tt.broadcast %34 : (tensor<16x1xf32, #blocked2>) -> tensor<16x16xf32, #blocked2>
  %42 = arith.subf %40, %41 : tensor<16x16xf32, #blocked2>
  %43 = math.exp %42 : tensor<16x16xf32, #blocked2>
  %44 = arith.addf %36, %43 : tensor<16x16xf32, #blocked2>
  %45 = "triton_gpu.select"(%22, %44, %36) : (tensor<16x16xi1, #blocked2>, tensor<16x16xf32, #blocked2>, tensor<16x16xf32, #blocked2>) -> tensor<16x16xf32, #blocked2>
  %46 = "tt.reduce" (%45) ({
  ^bb0(%arg4: f32, %arg5: f32):
    %add = arith.addf %arg4, %arg5 : f32
    tt.reduce.return %add : f32
  }) {axis = 1 : i32} : (tensor<16x16xf32, #blocked2>) -> tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
  %47 = triton_gpu.convert_layout %46 : (tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<16xf32, #blocked0>
  %48 = triton_gpu.convert_layout %47 : (tensor<16xf32, #blocked0>) -> tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>
  %49 = tt.expand_dims %48 {axis = 1 : i32} : (tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>) -> tensor<16x1xf32, #blocked1>
  %50 = triton_gpu.convert_layout %49 : (tensor<16x1xf32, #blocked1>) -> tensor<16x1xf32, #blocked2>
  %51 = triton_gpu.convert_layout %18 : (tensor<16x16x!tt.ptr<f32>, #blocked2>) -> tensor<16x16x!tt.ptr<f32>, #blocked4>
  %52 = triton_gpu.convert_layout %22 : (tensor<16x16xi1, #blocked2>) -> tensor<16x16xi1, #blocked4>
  %53 = tt.load %51, %52 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<16x16xf32, #blocked4>
  %54 = triton_gpu.convert_layout %53 : (tensor<16x16xf32, #blocked4>) -> tensor<16x16xf32, #blocked2>
  %55 = arith.subf %54, %41 : tensor<16x16xf32, #blocked2>
  %56 = math.log %50 : tensor<16x1xf32, #blocked2>
  %57 = tt.broadcast %56 : (tensor<16x1xf32, #blocked2>) -> tensor<16x16xf32, #blocked2>
  %58 = arith.subf %55, %57 : tensor<16x16xf32, #blocked2>
  %59 = tt.splat %arg1 : (!tt.ptr<f32>) -> tensor<16x16x!tt.ptr<f32>, #blocked2>
  %60 = tt.addptr %59, %16 : tensor<16x16x!tt.ptr<f32>, #blocked2>, tensor<16x16xi32, #blocked2>
  %61 = triton_gpu.convert_layout %60 : (tensor<16x16x!tt.ptr<f32>, #blocked2>) -> tensor<16x16x!tt.ptr<f32>, #blocked4>
  %62 = triton_gpu.convert_layout %58 : (tensor<16x16xf32, #blocked2>) -> tensor<16x16xf32, #blocked4>
  %63 = triton_gpu.convert_layout %22 : (tensor<16x16xi1, #blocked2>) -> tensor<16x16xi1, #blocked4>
  tt.store %61, %62, %63 : tensor<16x16xf32, #blocked4>
  tt.return
}
}

// -----

#blocked0 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [8], order = [0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [8, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked2 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [2, 4], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked3 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 8], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked4 = #triton_gpu.blocked<{sizePerThread = [1, 8], threadsPerWarp = [4, 8], warpsPerCTA = [8, 1], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked5 = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [2, 16], warpsPerCTA = [8, 1], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
// cmpf and cmpi have different operands and result types
// CHECK-LABEL: cmp
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func public @cmp(%arg0: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg2: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg3: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg4: i32 {tt.divisibility = 16 : i32}, %arg5: i32 {tt.divisibility = 16 : i32}) {
  %c64 = arith.constant 64 : index
  %c2048 = arith.constant 2048 : index
  %c0 = arith.constant 0 : index
  %c64_i32 = arith.constant 64 : i32
  %cst = arith.constant dense<-3.40282347E+38> : tensor<64x64xf32, #blocked2>
  %cst_0 = arith.constant dense<4194304> : tensor<64x1xi32, #blocked2>
  %cst_1 = arith.constant dense<12> : tensor<64x1xi32, #blocked2>
  %cst_2 = arith.constant dense<2048> : tensor<1x64xi32, #blocked3>
  %cst_3 = arith.constant dense<0> : tensor<64x64xi32, #blocked2>
  %cst_4 = arith.constant dense<2048> : tensor<64x1xi32, #blocked2>
  %cst_5 = arith.constant dense<49152> : tensor<64x1xi32, #blocked2>
  %cst_6 = arith.constant dense<0.000000e+00> : tensor<64x64xf32, #blocked2>
  %0 = tt.get_program_id x : i32
  %1 = arith.muli %0, %c64_i32 : i32
  %2 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #blocked0>
  %3 = triton_gpu.convert_layout %2 : (tensor<64xi32, #blocked0>) -> tensor<64xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>
  %4 = tt.expand_dims %3 {axis = 1 : i32} : (tensor<64xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>) -> tensor<64x1xi32, #blocked1>
  %5 = triton_gpu.convert_layout %4 : (tensor<64x1xi32, #blocked1>) -> tensor<64x1xi32, #blocked2>
  %6 = tt.splat %1 : (i32) -> tensor<64x1xi32, #blocked2>
  %7 = arith.addi %6, %5 : tensor<64x1xi32, #blocked2>
  %8 = "triton_gpu.cmpi"(%7, %cst_5) {predicate = 2 : i64} : (tensor<64x1xi32, #blocked2>, tensor<64x1xi32, #blocked2>) -> tensor<64x1xi1, #blocked2>
  %9 = triton_gpu.convert_layout %2 : (tensor<64xi32, #blocked0>) -> tensor<64xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>
  %10 = tt.expand_dims %9 {axis = 0 : i32} : (tensor<64xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>) -> tensor<1x64xi32, #blocked3>
  %11 = arith.remsi %7, %cst_4 : tensor<64x1xi32, #blocked2>
  %12 = arith.divsi %7, %cst_4 : tensor<64x1xi32, #blocked2>
  %13 = arith.sitofp %cst_3 : tensor<64x64xi32, #blocked2> to tensor<64x64xf32, #blocked2>
  %14 = arith.addf %13, %cst_6 : tensor<64x64xf32, #blocked2>
  %15 = arith.muli %7, %cst_4 : tensor<64x1xi32, #blocked2>
  %16 = tt.broadcast %15 : (tensor<64x1xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %17 = tt.splat %arg0 : (!tt.ptr<f16>) -> tensor<64x64x!tt.ptr<f16>, #blocked2>
  %18 = tt.broadcast %8 : (tensor<64x1xi1, #blocked2>) -> tensor<64x64xi1, #blocked2>
  %19 = arith.muli %11, %cst_4 : tensor<64x1xi32, #blocked2>
  %20 = tt.broadcast %19 : (tensor<64x1xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %21 = arith.divsi %12, %cst_1 : tensor<64x1xi32, #blocked2>
  %22 = arith.muli %21, %cst_0 : tensor<64x1xi32, #blocked2>
  %23 = tt.broadcast %22 : (tensor<64x1xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %24 = tt.splat %arg1 : (!tt.ptr<f32>) -> tensor<64x64x!tt.ptr<f32>, #blocked2>
  %25 = scf.for %arg6 = %c0 to %c2048 step %c64 iter_args(%arg7 = %14) -> (tensor<64x64xf32, #blocked2>) {
    %44 = arith.index_cast %arg6 : index to i32
    %45 = tt.splat %44 : (i32) -> tensor<1x64xi32, #blocked3>
    %46 = arith.addi %45, %10 : tensor<1x64xi32, #blocked3>
    %47 = "triton_gpu.cmpi"(%46, %cst_2) {predicate = 2 : i64} : (tensor<1x64xi32, #blocked3>, tensor<1x64xi32, #blocked3>) -> tensor<1x64xi1, #blocked3>
    %48 = tt.broadcast %46 : (tensor<1x64xi32, #blocked3>) -> tensor<64x64xi32, #blocked3>
    %49 = triton_gpu.convert_layout %48 : (tensor<64x64xi32, #blocked3>) -> tensor<64x64xi32, #blocked2>
    %50 = arith.addi %49, %16 : tensor<64x64xi32, #blocked2>
    %51 = tt.addptr %17, %50 : tensor<64x64x!tt.ptr<f16>, #blocked2>, tensor<64x64xi32, #blocked2>
    %52 = tt.broadcast %47 : (tensor<1x64xi1, #blocked3>) -> tensor<64x64xi1, #blocked3>
    %53 = triton_gpu.convert_layout %52 : (tensor<64x64xi1, #blocked3>) -> tensor<64x64xi1, #blocked2>
    %54 = arith.andi %53, %18 : tensor<64x64xi1, #blocked2>
    %55 = triton_gpu.convert_layout %51 : (tensor<64x64x!tt.ptr<f16>, #blocked2>) -> tensor<64x64x!tt.ptr<f16>, #blocked4>
    %56 = triton_gpu.convert_layout %54 : (tensor<64x64xi1, #blocked2>) -> tensor<64x64xi1, #blocked4>
    %57 = tt.load %55, %56 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<64x64xf16, #blocked4>
    %58 = triton_gpu.convert_layout %57 : (tensor<64x64xf16, #blocked4>) -> tensor<64x64xf16, #blocked2>
    %59 = arith.extf %58 : tensor<64x64xf16, #blocked2> to tensor<64x64xf32, #blocked2>
    %60 = arith.addi %49, %20 : tensor<64x64xi32, #blocked2>
    %61 = arith.addi %60, %23 : tensor<64x64xi32, #blocked2>
    %62 = tt.addptr %24, %61 : tensor<64x64x!tt.ptr<f32>, #blocked2>, tensor<64x64xi32, #blocked2>
    %63 = triton_gpu.convert_layout %62 : (tensor<64x64x!tt.ptr<f32>, #blocked2>) -> tensor<64x64x!tt.ptr<f32>, #blocked5>
    %64 = triton_gpu.convert_layout %54 : (tensor<64x64xi1, #blocked2>) -> tensor<64x64xi1, #blocked5>
    %65 = tt.load %63, %64 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<64x64xf32, #blocked5>
    %66 = triton_gpu.convert_layout %65 : (tensor<64x64xf32, #blocked5>) -> tensor<64x64xf32, #blocked2>
    %67 = arith.addf %59, %66 : tensor<64x64xf32, #blocked2>
    %68 = "triton_gpu.cmpf"(%67, %67) {predicate = 13 : i64} : (tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xi1, #blocked2>
    %69 = "triton_gpu.cmpf"(%67, %cst) {predicate = 2 : i64} : (tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xi1, #blocked2>
    %70 = "triton_gpu.select"(%69, %67, %cst) : (tensor<64x64xi1, #blocked2>, tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xf32, #blocked2>
    %71 = "triton_gpu.select"(%68, %67, %70) : (tensor<64x64xi1, #blocked2>, tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xf32, #blocked2>
    %72 = math.exp %71 : tensor<64x64xf32, #blocked2>
    %73 = arith.addf %arg7, %72 : tensor<64x64xf32, #blocked2>
    %74 = "triton_gpu.select"(%54, %73, %arg7) : (tensor<64x64xi1, #blocked2>, tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xf32, #blocked2>
    scf.yield %74 : tensor<64x64xf32, #blocked2>
  }
  %26 = "tt.reduce" (%25) ({
  ^bb0(%arg8: f32, %arg9: f32):
    %add = arith.addf %arg8, %arg9 : f32
    tt.reduce.return %add : f32
  }) {axis = 1 : i32} : (tensor<64x64xf32, #blocked2>) -> tensor<64xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
  %27 = triton_gpu.convert_layout %26 : (tensor<64xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<64xf32, #blocked0>
  %28 = triton_gpu.convert_layout %27 : (tensor<64xf32, #blocked0>) -> tensor<64xf32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>
  %29 = tt.expand_dims %28 {axis = 1 : i32} : (tensor<64xf32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>) -> tensor<64x1xf32, #blocked1>
  %30 = triton_gpu.convert_layout %29 : (tensor<64x1xf32, #blocked1>) -> tensor<64x1xf32, #blocked2>
  %31 = arith.muli %7, %cst_4 : tensor<64x1xi32, #blocked2>
  %32 = tt.broadcast %31 : (tensor<64x1xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %33 = tt.splat %arg0 : (!tt.ptr<f16>) -> tensor<64x64x!tt.ptr<f16>, #blocked2>
  %34 = tt.broadcast %8 : (tensor<64x1xi1, #blocked2>) -> tensor<64x64xi1, #blocked2>
  %35 = arith.muli %11, %cst_4 : tensor<64x1xi32, #blocked2>
  %36 = tt.broadcast %35 : (tensor<64x1xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %37 = arith.divsi %12, %cst_1 : tensor<64x1xi32, #blocked2>
  %38 = arith.muli %37, %cst_0 : tensor<64x1xi32, #blocked2>
  %39 = tt.broadcast %38 : (tensor<64x1xi32, #blocked2>) -> tensor<64x64xi32, #blocked2>
  %40 = tt.splat %arg1 : (!tt.ptr<f32>) -> tensor<64x64x!tt.ptr<f32>, #blocked2>
  %41 = tt.broadcast %30 : (tensor<64x1xf32, #blocked2>) -> tensor<64x64xf32, #blocked2>
  %42 = tt.splat %arg2 : (!tt.ptr<f32>) -> tensor<64x64x!tt.ptr<f32>, #blocked2>
  %43 = tt.splat %arg3 : (!tt.ptr<f16>) -> tensor<64x64x!tt.ptr<f16>, #blocked2>
  scf.for %arg6 = %c0 to %c2048 step %c64 {
    %44 = arith.index_cast %arg6 : index to i32
    %45 = tt.splat %44 : (i32) -> tensor<1x64xi32, #blocked3>
    %46 = arith.addi %45, %10 : tensor<1x64xi32, #blocked3>
    %47 = "triton_gpu.cmpi"(%46, %cst_2) {predicate = 2 : i64} : (tensor<1x64xi32, #blocked3>, tensor<1x64xi32, #blocked3>) -> tensor<1x64xi1, #blocked3>
    %48 = tt.broadcast %46 : (tensor<1x64xi32, #blocked3>) -> tensor<64x64xi32, #blocked3>
    %49 = triton_gpu.convert_layout %48 : (tensor<64x64xi32, #blocked3>) -> tensor<64x64xi32, #blocked2>
    %50 = arith.addi %49, %32 : tensor<64x64xi32, #blocked2>
    %51 = tt.addptr %33, %50 : tensor<64x64x!tt.ptr<f16>, #blocked2>, tensor<64x64xi32, #blocked2>
    %52 = tt.broadcast %47 : (tensor<1x64xi1, #blocked3>) -> tensor<64x64xi1, #blocked3>
    %53 = triton_gpu.convert_layout %52 : (tensor<64x64xi1, #blocked3>) -> tensor<64x64xi1, #blocked2>
    %54 = arith.andi %53, %34 : tensor<64x64xi1, #blocked2>
    %55 = triton_gpu.convert_layout %51 : (tensor<64x64x!tt.ptr<f16>, #blocked2>) -> tensor<64x64x!tt.ptr<f16>, #blocked4>
    %56 = triton_gpu.convert_layout %54 : (tensor<64x64xi1, #blocked2>) -> tensor<64x64xi1, #blocked4>
    %57 = tt.load %55, %56 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<64x64xf16, #blocked4>
    %58 = triton_gpu.convert_layout %57 : (tensor<64x64xf16, #blocked4>) -> tensor<64x64xf16, #blocked2>
    %59 = arith.extf %58 : tensor<64x64xf16, #blocked2> to tensor<64x64xf32, #blocked2>
    %60 = arith.addi %49, %36 : tensor<64x64xi32, #blocked2>
    %61 = arith.addi %60, %39 : tensor<64x64xi32, #blocked2>
    %62 = tt.addptr %40, %61 : tensor<64x64x!tt.ptr<f32>, #blocked2>, tensor<64x64xi32, #blocked2>
    %63 = triton_gpu.convert_layout %62 : (tensor<64x64x!tt.ptr<f32>, #blocked2>) -> tensor<64x64x!tt.ptr<f32>, #blocked5>
    %64 = triton_gpu.convert_layout %54 : (tensor<64x64xi1, #blocked2>) -> tensor<64x64xi1, #blocked5>
    %65 = tt.load %63, %64 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<64x64xf32, #blocked5>
    %66 = triton_gpu.convert_layout %65 : (tensor<64x64xf32, #blocked5>) -> tensor<64x64xf32, #blocked2>
    %67 = arith.addf %59, %66 : tensor<64x64xf32, #blocked2>
    %68 = "triton_gpu.cmpf"(%67, %67) {predicate = 13 : i64} : (tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xi1, #blocked2>
    %69 = "triton_gpu.cmpf"(%67, %cst) {predicate = 2 : i64} : (tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xi1, #blocked2>
    %70 = "triton_gpu.select"(%69, %67, %cst) : (tensor<64x64xi1, #blocked2>, tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xf32, #blocked2>
    %71 = "triton_gpu.select"(%68, %67, %70) : (tensor<64x64xi1, #blocked2>, tensor<64x64xf32, #blocked2>, tensor<64x64xf32, #blocked2>) -> tensor<64x64xf32, #blocked2>
    %72 = math.exp %71 : tensor<64x64xf32, #blocked2>
    %73 = arith.divf %72, %41 : tensor<64x64xf32, #blocked2>
    %74 = tt.addptr %42, %50 : tensor<64x64x!tt.ptr<f32>, #blocked2>, tensor<64x64xi32, #blocked2>
    %75 = triton_gpu.convert_layout %74 : (tensor<64x64x!tt.ptr<f32>, #blocked2>) -> tensor<64x64x!tt.ptr<f32>, #blocked5>
    %76 = triton_gpu.convert_layout %73 : (tensor<64x64xf32, #blocked2>) -> tensor<64x64xf32, #blocked5>
    %77 = triton_gpu.convert_layout %54 : (tensor<64x64xi1, #blocked2>) -> tensor<64x64xi1, #blocked5>
    tt.store %75, %76, %77 : tensor<64x64xf32, #blocked5>
    %78 = tt.addptr %43, %50 : tensor<64x64x!tt.ptr<f16>, #blocked2>, tensor<64x64xi32, #blocked2>
    %79 = arith.truncf %73 : tensor<64x64xf32, #blocked2> to tensor<64x64xf16, #blocked2>
    %80 = triton_gpu.convert_layout %78 : (tensor<64x64x!tt.ptr<f16>, #blocked2>) -> tensor<64x64x!tt.ptr<f16>, #blocked4>
    %81 = triton_gpu.convert_layout %79 : (tensor<64x64xf16, #blocked2>) -> tensor<64x64xf16, #blocked4>
    %82 = triton_gpu.convert_layout %54 : (tensor<64x64xi1, #blocked2>) -> tensor<64x64xi1, #blocked4>
    tt.store %80, %81, %82 : tensor<64x64xf16, #blocked4>
  }
  tt.return
}
}

// -----

// Just make sure it doesn't crash on non-tensor types.
// CHECK-LABEL: if_no_tensor
module attributes {"triton_gpu.num-warps" = 4 : i32} {
tt.func public @if_no_tensor(%arg0: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg2: i32 {tt.divisibility = 16 : i32}, %arg3: !tt.ptr<i64> {tt.divisibility = 16 : i32}) {
  // CHECK-NOT: triton_gpu.convert_layout
  %c-1_i64 = arith.constant -1 : i64
  %cst = arith.constant 0.000000e+00 : f32
  %c-1_i32 = arith.constant -1 : i32
  %0 = tt.get_program_id x : i32
  %1 = tt.addptr %arg3, %0 : !tt.ptr<i64>, i32
  %2 = tt.load %1 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : i64
  %3 = arith.cmpi eq, %2, %c-1_i64 : i64
  %4 = arith.select %3, %c-1_i32, %arg2 : i32
  %5 = scf.if %3 -> (!tt.ptr<f32>) {
    scf.yield %arg0 : !tt.ptr<f32>
  } else {
    %10 = tt.addptr %arg0, %2 : !tt.ptr<f32>, i64
    scf.yield %10 : !tt.ptr<f32>
  }
  %6 = arith.extsi %4 : i32 to i64
  %7 = arith.cmpi slt, %2, %6 : i64
  %8 = tt.load %5, %7, %cst {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : f32
  %9 = tt.addptr %arg1, %0 : !tt.ptr<f32>, i32
  tt.store %9, %8 {cache = 1 : i32, evict = 1 : i32} : f32
  tt.return
}
}

// -----

// Check if the SimplifyReduceCvt rewriter pattern doesn't hang.
// CHECK-LABEL: reduce_cvt
// CHECK-NOT: triton_gpu.convert_layout
#blocked = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 2], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [2], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
#blocked2 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [2, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked3 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [16, 2], warpsPerCTA = [2, 1], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
module attributes {"triton_gpu.num-warps" = 2 : i32} {
  tt.func public @reduce_cvt1(%arg0: !tt.ptr<i64> {tt.divisibility = 16 : i32}, %arg1: i32, %arg2: i32) {
    %cst = arith.constant dense<0> : tensor<1x2xi32, #blocked>
    %cst_0 = arith.constant dense<2> : tensor<1x2xi32, #blocked>
    %0 = tt.make_range {end = 2 : i32, start = 0 : i32} : tensor<2xi32, #blocked1>
    %1 = triton_gpu.convert_layout %0 : (tensor<2xi32, #blocked1>) -> tensor<2xi32, #triton_gpu.slice<{dim = 0, parent = #blocked}>>
    %2 = tt.expand_dims %1 {axis = 0 : i32} : (tensor<2xi32, #triton_gpu.slice<{dim = 0, parent = #blocked}>>) -> tensor<1x2xi32, #blocked>
    %3 = "triton_gpu.cmpi"(%2, %cst_0) {predicate = 2 : i64} : (tensor<1x2xi32, #blocked>, tensor<1x2xi32, #blocked>) -> tensor<1x2xi1, #blocked>
    %4 = "tt.reduce" (%cst) ({
    ^bb0(%arg3: i32, %arg4: i32):
      %add = arith.addi %arg3, %arg4 : i32
      tt.reduce.return %add : i32
    }) {axis = 1 : i32} : (tensor<1x2xi32, #blocked>) -> tensor<1xi32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>
    %5 = triton_gpu.convert_layout %4 : (tensor<1xi32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>) -> tensor<1xi32, #blocked1>
    %6 = triton_gpu.convert_layout %5 : (tensor<1xi32, #blocked1>) -> tensor<1xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
    %7 = tt.expand_dims %6 {axis = 1 : i32} : (tensor<1xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<1x1xi32, #blocked2>
    %8 = triton_gpu.convert_layout %7 : (tensor<1x1xi32, #blocked2>) -> tensor<1x1xi32, #blocked>
    %9 = tt.splat %arg0 : (!tt.ptr<i64>) -> tensor<1x2x!tt.ptr<i64>, #blocked>
    %10 = tt.addptr %9, %2 : tensor<1x2x!tt.ptr<i64>, #blocked>, tensor<1x2xi32, #blocked>
    %11 = tt.broadcast %8 : (tensor<1x1xi32, #blocked>) -> tensor<1x2xi32, #blocked>
    %12 = arith.extsi %11 : tensor<1x2xi32, #blocked> to tensor<1x2xi64, #blocked>
    %13 = triton_gpu.convert_layout %10 : (tensor<1x2x!tt.ptr<i64>, #blocked>) -> tensor<1x2x!tt.ptr<i64>, #blocked3>
    %14 = triton_gpu.convert_layout %12 : (tensor<1x2xi64, #blocked>) -> tensor<1x2xi64, #blocked3>
    %15 = triton_gpu.convert_layout %3 : (tensor<1x2xi1, #blocked>) -> tensor<1x2xi1, #blocked3>
    tt.store %13, %14, %15 {cache = 1 : i32, evict = 1 : i32} : tensor<1x2xi64, #blocked3>
    tt.return
  }
}

// -----

// CHECK-LABEL: reduce_cvt2
// Match the reduction
// CHECK-NOT: triton_gpu.convert_layout
// CHECK: tt.reduce
// CHECK-SAME: axis = 1
// CHECK: (tensor<1x256xf32, #{{.*}}>) -> tensor<1xf32, #triton_gpu.slice<{dim = 1, parent = #{{.*}}}>>
// CHECK: triton_gpu.convert_layout
// CHECK: tt.expand_dims
// CHECK-NOT: triton_gpu.convert_layout
// CHECK: tt.return
#blocked = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 4], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
#blocked2 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [4, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked3 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 4], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
module attributes {"triton_gpu.num-warps" = 4 : i32} {
  tt.func public @reduce_cvt2(%arg0: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg2: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg3: i32 {tt.divisibility = 16 : i32}, %arg4: i32 {tt.divisibility = 16 : i32}) {
    %cst = arith.constant dense<0.000000e+00> : tensor<1x256xf32, #blocked>
    %c3136_i32 = arith.constant 3136 : index
    %c256_i32 = arith.constant 256 : index
    %c0_i32 = arith.constant 0 : index
    %cst_0 = arith.constant dense<3.136000e+03> : tensor<1x1xf32, #blocked>
    %cst_1 = arith.constant dense<50176> : tensor<1x256xi32, #blocked>
    %cst_2 = arith.constant dense<196> : tensor<1x1xi32, #blocked>
    %cst_3 = arith.constant dense<196> : tensor<1x256xi32, #blocked>
    %cst_4 = arith.constant dense<3136> : tensor<1x256xi32, #blocked>
    %cst_5 = arith.constant dense<256> : tensor<1x1xi32, #blocked>
    %0 = tt.get_program_id x : i32
    %1 = tt.make_range {end = 1 : i32, start = 0 : i32} : tensor<1xi32, #blocked1>
    %2 = triton_gpu.convert_layout %1 : (tensor<1xi32, #blocked1>) -> tensor<1xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
    %3 = tt.expand_dims %2 {axis = 1 : i32} : (tensor<1xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<1x1xi32, #blocked2>
    %4 = triton_gpu.convert_layout %3 : (tensor<1x1xi32, #blocked2>) -> tensor<1x1xi32, #blocked>
    %5 = tt.splat %0 : (i32) -> tensor<1x1xi32, #blocked>
    %6 = arith.addi %5, %4 : tensor<1x1xi32, #blocked>
    %7 = "triton_gpu.cmpi"(%6, %cst_5) {predicate = 2 : i64} : (tensor<1x1xi32, #blocked>, tensor<1x1xi32, #blocked>) -> tensor<1x1xi1, #blocked>
    %8 = tt.make_range {end = 256 : i32, start = 0 : i32} : tensor<256xi32, #blocked1>
    %9 = triton_gpu.convert_layout %8 : (tensor<256xi32, #blocked1>) -> tensor<256xi32, #triton_gpu.slice<{dim = 0, parent = #blocked}>>
    %10 = tt.expand_dims %9 {axis = 0 : i32} : (tensor<256xi32, #triton_gpu.slice<{dim = 0, parent = #blocked}>>) -> tensor<1x256xi32, #blocked>
    %11 = arith.muli %6, %cst_2 : tensor<1x1xi32, #blocked>
    %12 = tt.broadcast %11 : (tensor<1x1xi32, #blocked>) -> tensor<1x256xi32, #blocked>
    %13 = tt.splat %arg1 : (!tt.ptr<f32>) -> tensor<1x256x!tt.ptr<f32>, #blocked>
    %14 = tt.broadcast %7 : (tensor<1x1xi1, #blocked>) -> tensor<1x256xi1, #blocked>
    %15 = scf.for %arg5 = %c0_i32 to %c3136_i32 step %c256_i32 iter_args(%arg6 = %cst) -> (tensor<1x256xf32, #blocked>) {
      %42 = arith.index_cast %arg5 : index to i32
      %43 = tt.splat %42 : (i32) -> tensor<1x256xi32, #blocked>
      %44 = arith.addi %43, %10 : tensor<1x256xi32, #blocked>
      %45 = "triton_gpu.cmpi"(%44, %cst_4) {predicate = 2 : i64} : (tensor<1x256xi32, #blocked>, tensor<1x256xi32, #blocked>) -> tensor<1x256xi1, #blocked>
      %46 = arith.remsi %44, %cst_3 : tensor<1x256xi32, #blocked>
      %47 = arith.divsi %44, %cst_3 : tensor<1x256xi32, #blocked>
      %48 = arith.addi %46, %12 : tensor<1x256xi32, #blocked>
      %49 = arith.muli %47, %cst_1 : tensor<1x256xi32, #blocked>
      %50 = arith.addi %48, %49 : tensor<1x256xi32, #blocked>
      %51 = tt.addptr %13, %50 : tensor<1x256x!tt.ptr<f32>, #blocked>, tensor<1x256xi32, #blocked>
      %52 = arith.andi %45, %14 : tensor<1x256xi1, #blocked>
      %53 = triton_gpu.convert_layout %51 : (tensor<1x256x!tt.ptr<f32>, #blocked>) -> tensor<1x256x!tt.ptr<f32>, #blocked3>
      %54 = triton_gpu.convert_layout %52 : (tensor<1x256xi1, #blocked>) -> tensor<1x256xi1, #blocked3>
      %55 = triton_gpu.convert_layout %cst : (tensor<1x256xf32, #blocked>) -> tensor<1x256xf32, #blocked3>
      %56 = tt.load %53, %54, %55 {cache = 1 : i32, evict = 3 : i32, isVolatile = false} : tensor<1x256xf32, #blocked3>
      %57 = triton_gpu.convert_layout %56 : (tensor<1x256xf32, #blocked3>) -> tensor<1x256xf32, #blocked>
      %58 = arith.addf %arg6, %57 : tensor<1x256xf32, #blocked>
      %59 = "triton_gpu.select"(%52, %58, %arg6) : (tensor<1x256xi1, #blocked>, tensor<1x256xf32, #blocked>, tensor<1x256xf32, #blocked>) -> tensor<1x256xf32, #blocked>
      scf.yield %59 : tensor<1x256xf32, #blocked>
    }
    %16 = "tt.reduce" (%15) ({
    ^bb0(%arg7: f32, %arg8: f32):
      %add = arith.addf %arg7, %arg8 : f32
      tt.reduce.return %add : f32

    }) {axis = 1 : i32} : (tensor<1x256xf32, #blocked>) -> tensor<1xf32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>
    %17 = triton_gpu.convert_layout %16 : (tensor<1xf32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>) -> tensor<1xf32, #blocked1>
    %18 = triton_gpu.convert_layout %17 : (tensor<1xf32, #blocked1>) -> tensor<1xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
    %19 = tt.expand_dims %18 {axis = 1 : i32} : (tensor<1xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<1x1xf32, #blocked2>
    %20 = triton_gpu.convert_layout %19 : (tensor<1x1xf32, #blocked2>) -> tensor<1x1xf32, #blocked>
    %21 = arith.divf %20, %cst_0 : tensor<1x1xf32, #blocked>
    %22 = tt.splat %arg0 : (!tt.ptr<f32>) -> tensor<1x1x!tt.ptr<f32>, #blocked>
    %23 = tt.addptr %22, %6 : tensor<1x1x!tt.ptr<f32>, #blocked>, tensor<1x1xi32, #blocked>
    %24 = triton_gpu.convert_layout %23 : (tensor<1x1x!tt.ptr<f32>, #blocked>) -> tensor<1x1x!tt.ptr<f32>, #blocked>
    %25 = triton_gpu.convert_layout %21 : (tensor<1x1xf32, #blocked>) -> tensor<1x1xf32, #blocked>
    %26 = triton_gpu.convert_layout %7 : (tensor<1x1xi1, #blocked>) -> tensor<1x1xi1, #blocked>
    tt.store %24, %25, %26 {cache = 1 : i32, evict = 1 : i32} : tensor<1x1xf32, #blocked>
    tt.return
  }
}

// -----

// Ensure that RematerializeForward doesn't apply when a convert has multiple uses
// CHECK-LABEL: loop_convert_multi_uses
#blocked = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [16, 2], warpsPerCTA = [1, 4], order = [0, 1]}>
#blocked2 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [4, 1], order = [0, 1]}>
#blocked3 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 4], order = [0, 1]}>
#blocked4 = #triton_gpu.blocked<{sizePerThread = [1, 2], threadsPerWarp = [4, 8], warpsPerCTA = [4, 1], order = [1, 0]}>
module attributes {"triton_gpu.num-warps" = 4 : i32, "triton_gpu.threads-per-warp" = 32 : i32} {
  tt.func public @loop_convert_multi_uses(%arg0: i32 {tt.divisibility = 16 : i32}, %arg1: i32, %arg2: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg3: i32 {tt.divisibility = 16 : i32}, %arg4: i32 {tt.divisibility = 16 : i32}, %arg5: i32 {tt.divisibility = 16 : i32}, %arg6: i32 {tt.divisibility = 16 : i32}, %arg7: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg8: i32 {tt.divisibility = 16 : i32}, %arg9: i32, %arg10: !tt.ptr<f32> {tt.divisibility = 16 : i32}, %arg11: i32 {tt.divisibility = 16 : i32}, %arg12: i32, %arg13: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg14: i32 {tt.divisibility = 16 : i32}, %arg15: i32 {tt.divisibility = 16 : i32}, %arg16: i32 {tt.divisibility = 16 : i32}) attributes {noinline = false} {
    %cst = arith.constant dense<0xFF800000> : tensor<16xf32, #blocked>
    %c1_i32 = arith.constant 1 : i32
    %c0_i32 = arith.constant 0 : i32
    %cst_0 = arith.constant dense<0.000000e+00> : tensor<16xf32, #blocked>
    %cst_1 = arith.constant dense<1> : tensor<16xi32, #blocked>
    %cst_2 = arith.constant dense<0.000000e+00> : tensor<16x16xf32, #blocked1>
    %cst_3 = arith.constant dense<1> : tensor<16x1xi32, #blocked1>
    %c16_i32 = arith.constant 16 : i32
    %0 = tt.get_program_id x : i32
    %1 = tt.get_program_id y : i32
    %2 = arith.divsi %1, %arg0 : i32
    %3 = arith.remsi %1, %arg0 : i32
    %4 = tt.make_range {end = 16 : i32, start = 0 : i32} : tensor<16xi32, #blocked>
    %5 = arith.muli %0, %c16_i32 : i32
    %6 = tt.splat %5 : (i32) -> tensor<16xi32, #blocked>
    %7 = arith.addi %6, %4 : tensor<16xi32, #blocked>
    %8 = arith.muli %2, %arg3 : i32
    %9 = arith.muli %3, %arg4 : i32
    %10 = arith.addi %8, %9 : i32
    %11 = triton_gpu.convert_layout %7 : (tensor<16xi32, #blocked>) -> tensor<16xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
    %12 = tt.expand_dims %11 {axis = 1 : i32} : (tensor<16xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<16x1xi32, #blocked2>
    %13 = triton_gpu.convert_layout %12 : (tensor<16x1xi32, #blocked2>) -> tensor<16x1xi32, #blocked1>
    %14 = tt.splat %arg6 : (i32) -> tensor<16x1xi32, #blocked1>
    %15 = arith.muli %13, %14 : tensor<16x1xi32, #blocked1>
    %16 = triton_gpu.convert_layout %4 : (tensor<16xi32, #blocked>) -> tensor<16xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>
    %17 = tt.expand_dims %16 {axis = 0 : i32} : (tensor<16xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>) -> tensor<1x16xi32, #blocked3>
    %18 = tt.broadcast %15 : (tensor<16x1xi32, #blocked1>) -> tensor<16x16xi32, #blocked1>
    %19 = tt.broadcast %17 : (tensor<1x16xi32, #blocked3>) -> tensor<16x16xi32, #blocked3>
    %20 = triton_gpu.convert_layout %19 : (tensor<16x16xi32, #blocked3>) -> tensor<16x16xi32, #blocked1>
    %21 = arith.addi %18, %20 : tensor<16x16xi32, #blocked1>
    %22 = tt.splat %arg2 : (!tt.ptr<f16>) -> tensor<16x16x!tt.ptr<f16>, #blocked1>
    %23 = "triton_gpu.cmpi"(%13, %cst_3) <{predicate = 2 : i64}> : (tensor<16x1xi32, #blocked1>, tensor<16x1xi32, #blocked1>) -> tensor<16x1xi1, #blocked1>
    %24 = tt.broadcast %23 : (tensor<16x1xi1, #blocked1>) -> tensor<16x16xi1, #blocked1>
    %25 = arith.truncf %cst_2 : tensor<16x16xf32, #blocked1> to tensor<16x16xf16, #blocked1>
    %26 = arith.muli %2, %arg11 : i32
    %27 = arith.muli %3, %arg12 : i32
    %28 = arith.addi %26, %27 : i32
    %29 = tt.splat %arg10 : (!tt.ptr<f32>) -> tensor<16x!tt.ptr<f32>, #blocked>
    %30 = "triton_gpu.cmpi"(%7, %cst_1) <{predicate = 2 : i64}> : (tensor<16xi32, #blocked>, tensor<16xi32, #blocked>) -> tensor<16xi1, #blocked>
    %31 = arith.muli %2, %arg8 : i32
    %32 = arith.muli %3, %arg9 : i32
    %33 = arith.addi %31, %32 : i32
    %34 = tt.splat %arg7 : (!tt.ptr<f32>) -> tensor<16x!tt.ptr<f32>, #blocked>
    %35:3 = scf.for %arg17 = %c0_i32 to %arg1 step %c1_i32 iter_args(%arg18 = %cst_2, %arg19 = %cst_0, %arg20 = %cst) -> (tensor<16x16xf32, #blocked1>, tensor<16xf32, #blocked>, tensor<16xf32, #blocked>)  : i32 {
      %60 = arith.muli %arg17, %arg5 : i32
      %61 = arith.addi %10, %60 : i32
      %62 = tt.splat %61 : (i32) -> tensor<16x16xi32, #blocked1>
      %63 = arith.addi %62, %21 : tensor<16x16xi32, #blocked1>
      %64 = tt.addptr %22, %63 : tensor<16x16x!tt.ptr<f16>, #blocked1>, tensor<16x16xi32, #blocked1>
      %65 = triton_gpu.convert_layout %64 : (tensor<16x16x!tt.ptr<f16>, #blocked1>) -> tensor<16x16x!tt.ptr<f16>, #blocked4>
      %66 = triton_gpu.convert_layout %24 : (tensor<16x16xi1, #blocked1>) -> tensor<16x16xi1, #blocked4>
      %67 = triton_gpu.convert_layout %25 : (tensor<16x16xf16, #blocked1>) -> tensor<16x16xf16, #blocked4>
      %68 = tt.load %65, %66, %67 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #blocked4>
      %69 = triton_gpu.convert_layout %68 : (tensor<16x16xf16, #blocked4>) -> tensor<16x16xf16, #blocked1>
      %70 = arith.addi %28, %arg17 : i32
      %71 = tt.splat %70 : (i32) -> tensor<16xi32, #blocked>
      %72 = arith.addi %71, %7 : tensor<16xi32, #blocked>
      %73 = tt.addptr %29, %72 : tensor<16x!tt.ptr<f32>, #blocked>, tensor<16xi32, #blocked>
      %74 = triton_gpu.convert_layout %73 : (tensor<16x!tt.ptr<f32>, #blocked>) -> tensor<16x!tt.ptr<f32>, #blocked>
      %75 = triton_gpu.convert_layout %30 : (tensor<16xi1, #blocked>) -> tensor<16xi1, #blocked>
      %76 = triton_gpu.convert_layout %cst_0 : (tensor<16xf32, #blocked>) -> tensor<16xf32, #blocked>
      %77 = tt.load %74, %75, %76 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16xf32, #blocked>
      %78 = arith.addi %33, %arg17 : i32
      %79 = tt.splat %78 : (i32) -> tensor<16xi32, #blocked>
      %80 = arith.addi %79, %7 : tensor<16xi32, #blocked>
      %81 = tt.addptr %34, %80 : tensor<16x!tt.ptr<f32>, #blocked>, tensor<16xi32, #blocked>
      %82 = triton_gpu.convert_layout %81 : (tensor<16x!tt.ptr<f32>, #blocked>) -> tensor<16x!tt.ptr<f32>, #blocked>
      %83 = triton_gpu.convert_layout %30 : (tensor<16xi1, #blocked>) -> tensor<16xi1, #blocked>
      %84 = triton_gpu.convert_layout %cst_0 : (tensor<16xf32, #blocked>) -> tensor<16xf32, #blocked>
      %85 = tt.load %82, %83, %84 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16xf32, #blocked>
      %86 = "triton_gpu.cmpf"(%arg20, %85) <{predicate = 2 : i64}> : (tensor<16xf32, #blocked>, tensor<16xf32, #blocked>) -> tensor<16xi1, #blocked>
      %87 = "triton_gpu.select"(%86, %arg20, %85) : (tensor<16xi1, #blocked>, tensor<16xf32, #blocked>, tensor<16xf32, #blocked>) -> tensor<16xf32, #blocked>
      %88 = arith.subf %arg20, %87 : tensor<16xf32, #blocked>
      %89 = math.exp %88 : tensor<16xf32, #blocked>
      %90 = arith.subf %85, %87 : tensor<16xf32, #blocked>
      %91 = math.exp %90 : tensor<16xf32, #blocked>
      %92 = arith.mulf %89, %arg19 : tensor<16xf32, #blocked>
      %93 = arith.mulf %91, %77 : tensor<16xf32, #blocked>
      %94 = arith.addf %92, %93 : tensor<16xf32, #blocked>
      %95 = arith.divf %91, %94 : tensor<16xf32, #blocked>
      %96 = arith.divf %arg19, %94 : tensor<16xf32, #blocked>
      %97 = arith.mulf %96, %89 : tensor<16xf32, #blocked>
      %98 = triton_gpu.convert_layout %97 : (tensor<16xf32, #blocked>) -> tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
      %99 = tt.expand_dims %98 {axis = 1 : i32} : (tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<16x1xf32, #blocked2>
      %100 = triton_gpu.convert_layout %99 : (tensor<16x1xf32, #blocked2>) -> tensor<16x1xf32, #blocked1>
      %101 = tt.broadcast %100 : (tensor<16x1xf32, #blocked1>) -> tensor<16x16xf32, #blocked1>
      %102 = arith.mulf %arg18, %101 : tensor<16x16xf32, #blocked1>
      %103 = triton_gpu.convert_layout %95 : (tensor<16xf32, #blocked>) -> tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
      %104 = tt.expand_dims %103 {axis = 1 : i32} : (tensor<16xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<16x1xf32, #blocked2>
      %105 = triton_gpu.convert_layout %104 : (tensor<16x1xf32, #blocked2>) -> tensor<16x1xf32, #blocked1>
      %106 = tt.broadcast %105 : (tensor<16x1xf32, #blocked1>) -> tensor<16x16xf32, #blocked1>
      %107 = arith.extf %69 : tensor<16x16xf16, #blocked1> to tensor<16x16xf32, #blocked1>
      %108 = arith.mulf %107, %106 : tensor<16x16xf32, #blocked1>
      %109 = arith.addf %102, %108 : tensor<16x16xf32, #blocked1>
      scf.yield %109, %94, %87 : tensor<16x16xf32, #blocked1>, tensor<16xf32, #blocked>, tensor<16xf32, #blocked>
    }
    %36 = arith.muli %2, %arg14 : i32
    %37 = arith.muli %3, %arg15 : i32
    %38 = arith.addi %36, %37 : i32
    %39 = triton_gpu.convert_layout %7 : (tensor<16xi32, #blocked>) -> tensor<16xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
    %40 = tt.expand_dims %39 {axis = 1 : i32} : (tensor<16xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<16x1xi32, #blocked2>
    %41 = triton_gpu.convert_layout %40 : (tensor<16x1xi32, #blocked2>) -> tensor<16x1xi32, #blocked1>
    %42 = tt.splat %arg16 : (i32) -> tensor<16x1xi32, #blocked1>
    %43 = arith.muli %41, %42 : tensor<16x1xi32, #blocked1>
    %44 = triton_gpu.convert_layout %4 : (tensor<16xi32, #blocked>) -> tensor<16xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>
    %45 = tt.expand_dims %44 {axis = 0 : i32} : (tensor<16xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>) -> tensor<1x16xi32, #blocked3>
    %46 = tt.broadcast %43 : (tensor<16x1xi32, #blocked1>) -> tensor<16x16xi32, #blocked1>
    %47 = tt.broadcast %45 : (tensor<1x16xi32, #blocked3>) -> tensor<16x16xi32, #blocked3>
    %48 = triton_gpu.convert_layout %47 : (tensor<16x16xi32, #blocked3>) -> tensor<16x16xi32, #blocked1>
    %49 = arith.addi %46, %48 : tensor<16x16xi32, #blocked1>
    %50 = tt.splat %38 : (i32) -> tensor<16x16xi32, #blocked1>
    %51 = arith.addi %50, %49 : tensor<16x16xi32, #blocked1>
    %52 = tt.splat %arg13 : (!tt.ptr<f16>) -> tensor<16x16x!tt.ptr<f16>, #blocked1>
    %53 = tt.addptr %52, %51 : tensor<16x16x!tt.ptr<f16>, #blocked1>, tensor<16x16xi32, #blocked1>
    %54 = "triton_gpu.cmpi"(%41, %cst_3) <{predicate = 2 : i64}> : (tensor<16x1xi32, #blocked1>, tensor<16x1xi32, #blocked1>) -> tensor<16x1xi1, #blocked1>
    %55 = tt.broadcast %54 : (tensor<16x1xi1, #blocked1>) -> tensor<16x16xi1, #blocked1>
    %56 = arith.truncf %35#0 : tensor<16x16xf32, #blocked1> to tensor<16x16xf16, #blocked1>
    %57 = triton_gpu.convert_layout %53 : (tensor<16x16x!tt.ptr<f16>, #blocked1>) -> tensor<16x16x!tt.ptr<f16>, #blocked4>
    %58 = triton_gpu.convert_layout %56 : (tensor<16x16xf16, #blocked1>) -> tensor<16x16xf16, #blocked4>
    %59 = triton_gpu.convert_layout %55 : (tensor<16x16xi1, #blocked1>) -> tensor<16x16xi1, #blocked4>
    tt.store %57, %58, %59 {cache = 1 : i32, evict = 1 : i32} : tensor<16x16xf16, #blocked4>
    tt.return
  }
}

// -----

// Check if MoveConvertOutOfLoop hangs because of adding additional conversions
// CHECK-LABEL: loop_print
// CHECK-NOT: triton_gpu.convert_layout
//     CHECK: tt.return
#blocked = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [1, 4], order = [0, 1]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [4, 1], order = [0, 1]}>
#blocked2 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0]}>
#blocked3 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 4], order = [0, 1]}>
#blocked4 = #triton_gpu.blocked<{sizePerThread = [1, 8], threadsPerWarp = [8, 4], warpsPerCTA = [4, 1], order = [1, 0]}>
#blocked5 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 4], order = [1, 0]}>
module attributes {"triton_gpu.num-warps" = 4 : i32, "triton_gpu.threads-per-warp" = 32 : i32} {
  tt.func public @loop_print(%arg0: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg2: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg3: i32 {tt.divisibility = 16 : i32}, %arg4: i32 {tt.divisibility = 16 : i32}, %arg5: i32 {tt.divisibility = 16 : i32}, %arg6: i32 {tt.divisibility = 16 : i32}) attributes {noinline = false} {
    %c32_i32 = arith.constant 32 : i32
    %c31_i32 = arith.constant 31 : i32
    %c0_i32 = arith.constant 0 : i32
    %c1_i32 = arith.constant 1 : i32
    %cst = arith.constant dense<32> : tensor<32x128xi32, #blocked>
    %cst_0 = arith.constant dense<32> : tensor<128x32xi32, #blocked1>
    %cst_1 = arith.constant 0.000000e+00 : f32
    %0 = tt.make_range {end = 128 : i32, start = 0 : i32} : tensor<128xi32, #blocked2>
    %1 = triton_gpu.convert_layout %0 : (tensor<128xi32, #blocked2>) -> tensor<128xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>
    %2 = tt.expand_dims %1 {axis = 1 : i32} : (tensor<128xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>) -> tensor<128x1xi32, #blocked1>
    %3 = tt.splat %arg6 : (i32) -> tensor<128x1xi32, #blocked1>
    %4 = arith.muli %2, %3 : tensor<128x1xi32, #blocked1>
    %5 = tt.make_range {end = 32 : i32, start = 0 : i32} : tensor<32xi32, #blocked2>
    %6 = triton_gpu.convert_layout %5 : (tensor<32xi32, #blocked2>) -> tensor<32xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>
    %7 = tt.expand_dims %6 {axis = 0 : i32} : (tensor<32xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>) -> tensor<1x32xi32, #blocked3>
    %8 = tt.broadcast %4 : (tensor<128x1xi32, #blocked1>) -> tensor<128x32xi32, #blocked1>
    %9 = tt.broadcast %7 : (tensor<1x32xi32, #blocked3>) -> tensor<128x32xi32, #blocked3>
    %10 = triton_gpu.convert_layout %9 : (tensor<128x32xi32, #blocked3>) -> tensor<128x32xi32, #blocked1>
    %11 = arith.addi %8, %10 : tensor<128x32xi32, #blocked1>
    %12 = triton_gpu.convert_layout %5 : (tensor<32xi32, #blocked2>) -> tensor<32xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>
    %13 = tt.expand_dims %12 {axis = 1 : i32} : (tensor<32xi32, #triton_gpu.slice<{dim = 1, parent = #blocked1}>>) -> tensor<32x1xi32, #blocked1>
    %14 = triton_gpu.convert_layout %13 : (tensor<32x1xi32, #blocked1>) -> tensor<32x1xi32, #blocked>
    %15 = triton_gpu.convert_layout %0 : (tensor<128xi32, #blocked2>) -> tensor<128xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>
    %16 = tt.expand_dims %15 {axis = 0 : i32} : (tensor<128xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>) -> tensor<1x128xi32, #blocked3>
    %17 = tt.broadcast %14 : (tensor<32x1xi32, #blocked>) -> tensor<32x128xi32, #blocked>
    %18 = tt.broadcast %16 : (tensor<1x128xi32, #blocked3>) -> tensor<32x128xi32, #blocked3>
    %19 = triton_gpu.convert_layout %18 : (tensor<32x128xi32, #blocked3>) -> tensor<32x128xi32, #blocked>
    %20 = arith.addi %17, %19 : tensor<32x128xi32, #blocked>
    %21 = arith.addi %arg5, %c31_i32 : i32
    %22 = arith.divsi %21, %c32_i32 : i32
    %23 = tt.splat %arg0 : (!tt.ptr<f16>) -> tensor<128x32x!tt.ptr<f16>, #blocked1>
    %24 = tt.splat %arg1 : (!tt.ptr<f16>) -> tensor<32x128x!tt.ptr<f16>, #blocked>
    %25:3 = scf.for %arg7 = %c0_i32 to %22 step %c1_i32 iter_args(%arg8 = %cst_1, %arg9 = %11, %arg10 = %20) -> (f32, tensor<128x32xi32, #blocked1>, tensor<32x128xi32, #blocked>)  : i32 {
      tt.print "a_offsets: " : %arg9 : tensor<128x32xi32, #blocked1>
      %27 = tt.addptr %23, %arg9 : tensor<128x32x!tt.ptr<f16>, #blocked1>, tensor<128x32xi32, #blocked1>
      %28 = triton_gpu.convert_layout %27 : (tensor<128x32x!tt.ptr<f16>, #blocked1>) -> tensor<128x32x!tt.ptr<f16>, #blocked4>
      %29 = tt.load %28 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<128x32xf16, #blocked4>
      %30 = triton_gpu.convert_layout %29 : (tensor<128x32xf16, #blocked4>) -> tensor<128x32xf16, #blocked1>
      %31 = tt.addptr %24, %arg10 : tensor<32x128x!tt.ptr<f16>, #blocked>, tensor<32x128xi32, #blocked>
      %32 = triton_gpu.convert_layout %31 : (tensor<32x128x!tt.ptr<f16>, #blocked>) -> tensor<32x128x!tt.ptr<f16>, #blocked5>
      %33 = tt.load %32 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<32x128xf16, #blocked5>
      %34 = triton_gpu.convert_layout %33 : (tensor<32x128xf16, #blocked5>) -> tensor<32x128xf16, #blocked>
      %35 = "tt.reduce"(%30) <{axis = 0 : i32}> ({
      ^bb0(%arg11: f16, %arg12: f16):
        %46 = arith.addf %arg11, %arg12 : f16
        tt.reduce.return %46 : f16
      }) : (tensor<128x32xf16, #blocked1>) -> tensor<32xf16, #triton_gpu.slice<{dim = 0, parent = #blocked1}>>
      %36 = triton_gpu.convert_layout %35 : (tensor<32xf16, #triton_gpu.slice<{dim = 0, parent = #blocked1}>>) -> tensor<32xf16, #blocked2>
      %37 = "tt.reduce"(%36) <{axis = 0 : i32}> ({
      ^bb0(%arg11: f16, %arg12: f16):
        %46 = arith.addf %arg11, %arg12 : f16
        tt.reduce.return %46 : f16
      }) : (tensor<32xf16, #blocked2>) -> f16
      %38 = "tt.reduce"(%34) <{axis = 0 : i32}> ({
      ^bb0(%arg11: f16, %arg12: f16):
        %46 = arith.addf %arg11, %arg12 : f16
        tt.reduce.return %46 : f16
      }) : (tensor<32x128xf16, #blocked>) -> tensor<128xf16, #triton_gpu.slice<{dim = 0, parent = #blocked}>>
      %39 = triton_gpu.convert_layout %38 : (tensor<128xf16, #triton_gpu.slice<{dim = 0, parent = #blocked}>>) -> tensor<128xf16, #blocked2>
      %40 = "tt.reduce"(%39) <{axis = 0 : i32}> ({
      ^bb0(%arg11: f16, %arg12: f16):
        %46 = arith.addf %arg11, %arg12 : f16
        tt.reduce.return %46 : f16
      }) : (tensor<128xf16, #blocked2>) -> f16
      %41 = arith.addf %37, %40 : f16
      %42 = arith.extf %41 : f16 to f32
      %43 = arith.addf %arg8, %42 : f32
      %44 = arith.addi %arg9, %cst_0 : tensor<128x32xi32, #blocked1>
      %45 = arith.addi %arg10, %cst : tensor<32x128xi32, #blocked>
      scf.yield %43, %44, %45 : f32, tensor<128x32xi32, #blocked1>, tensor<32x128xi32, #blocked>
    }
    %26 = arith.truncf %25#0 : f32 to f16
    tt.store %arg2, %26 {cache = 1 : i32, evict = 1 : i32} : f16
    tt.return
  }
}

// -----

// Check if SimplifyReduceCvt handles the cvt,reduce->reduce,cvt conversion but not the general push forward conversion
// CHECK-LABEL: reduce_cvt3
// CHECK: tt.dot
// CHECK-NEXT: tt.reduce
// CHECK: triton_gpu.convert_layout
#blocked = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [1, 4], order = [0, 1]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0]}>
#blocked2 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [4, 1], order = [0, 1]}>
#blocked3 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 4], order = [0, 1]}>
#blocked4 = #triton_gpu.blocked<{sizePerThread = [1, 8], threadsPerWarp = [8, 4], warpsPerCTA = [4, 1], order = [1, 0]}>
#blocked5 = #triton_gpu.blocked<{sizePerThread = [2, 2], threadsPerWarp = [2, 16], warpsPerCTA = [4, 1], order = [1, 0]}>
#shared = #triton_gpu.shared<{vec = 1, perPhase = 1, maxPhase = 1, order = [0, 1]}>
#shared1 = #triton_gpu.shared<{vec = 1, perPhase = 1, maxPhase = 1, order = [1, 0]}>
module attributes {"triton_gpu.num-warps" = 4 : i32, "triton_gpu.threads-per-warp" = 32 : i32} {
  tt.func public @reduce_cvt3(%arg0: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f16> {tt.divisibility = 16 : i32}, %arg2: !tt.ptr<i32> {tt.divisibility = 16 : i32}) attributes {noinline = false} {
    %cst = arith.constant dense<0.000000e+00> : tensor<32x32xf32, #blocked>
    %cst_0 = arith.constant dense<32> : tensor<32x1xi32, #blocked>
    %0 = tt.make_range {end = 32 : i32, start = 0 : i32} : tensor<32xi32, #blocked1>
    %1 = triton_gpu.convert_layout %0 : (tensor<32xi32, #blocked1>) -> tensor<32xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
    %2 = tt.expand_dims %1 {axis = 1 : i32} : (tensor<32xi32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<32x1xi32, #blocked2>
    %3 = triton_gpu.convert_layout %2 : (tensor<32x1xi32, #blocked2>) -> tensor<32x1xi32, #blocked>
    %4 = arith.muli %3, %cst_0 : tensor<32x1xi32, #blocked>
    %5 = tt.splat %arg0 : (!tt.ptr<f16>) -> tensor<32x1x!tt.ptr<f16>, #blocked>
    %6 = tt.addptr %5, %4 : tensor<32x1x!tt.ptr<f16>, #blocked>, tensor<32x1xi32, #blocked>
    %7 = triton_gpu.convert_layout %0 : (tensor<32xi32, #blocked1>) -> tensor<32xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>
    %8 = tt.expand_dims %7 {axis = 0 : i32} : (tensor<32xi32, #triton_gpu.slice<{dim = 0, parent = #blocked3}>>) -> tensor<1x32xi32, #blocked3>
    %9 = tt.broadcast %6 : (tensor<32x1x!tt.ptr<f16>, #blocked>) -> tensor<32x32x!tt.ptr<f16>, #blocked>
    %10 = tt.broadcast %8 : (tensor<1x32xi32, #blocked3>) -> tensor<32x32xi32, #blocked3>
    %11 = triton_gpu.convert_layout %10 : (tensor<32x32xi32, #blocked3>) -> tensor<32x32xi32, #blocked>
    %12 = tt.addptr %9, %11 : tensor<32x32x!tt.ptr<f16>, #blocked>, tensor<32x32xi32, #blocked>
    %13 = tt.splat %arg1 : (!tt.ptr<f16>) -> tensor<32x1x!tt.ptr<f16>, #blocked>
    %14 = tt.addptr %13, %4 : tensor<32x1x!tt.ptr<f16>, #blocked>, tensor<32x1xi32, #blocked>
    %15 = tt.broadcast %14 : (tensor<32x1x!tt.ptr<f16>, #blocked>) -> tensor<32x32x!tt.ptr<f16>, #blocked>
    %16 = tt.addptr %15, %11 : tensor<32x32x!tt.ptr<f16>, #blocked>, tensor<32x32xi32, #blocked>
    %17 = triton_gpu.convert_layout %12 : (tensor<32x32x!tt.ptr<f16>, #blocked>) -> tensor<32x32x!tt.ptr<f16>, #blocked4>
    %18 = tt.load %17 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<32x32xf16, #blocked4>
    %19 = triton_gpu.convert_layout %18 : (tensor<32x32xf16, #blocked4>) -> tensor<32x32xf16, #blocked>
    %20 = triton_gpu.convert_layout %16 : (tensor<32x32x!tt.ptr<f16>, #blocked>) -> tensor<32x32x!tt.ptr<f16>, #blocked4>
    %21 = tt.load %20 {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<32x32xf16, #blocked4>
    %22 = triton_gpu.convert_layout %21 : (tensor<32x32xf16, #blocked4>) -> tensor<32x32xf16, #blocked>
    %23 = triton_gpu.convert_layout %22 : (tensor<32x32xf16, #blocked>) -> tensor<32x32xf16, #shared>
    %24 = tt.trans %23 : (tensor<32x32xf16, #shared>) -> tensor<32x32xf16, #shared1>
    %25 = triton_gpu.convert_layout %24 : (tensor<32x32xf16, #shared1>) -> tensor<32x32xf16, #blocked>
    %26 = triton_gpu.convert_layout %19 : (tensor<32x32xf16, #blocked>) -> tensor<32x32xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #blocked5}>>
    %27 = triton_gpu.convert_layout %25 : (tensor<32x32xf16, #blocked>) -> tensor<32x32xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #blocked5}>>
    %28 = triton_gpu.convert_layout %cst : (tensor<32x32xf32, #blocked>) -> tensor<32x32xf32, #blocked5>
    %29 = tt.dot %26, %27, %28 {allowTF32 = true, maxNumImpreciseAcc = 0 : i32} : tensor<32x32xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #blocked5}>> * tensor<32x32xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #blocked5}>> -> tensor<32x32xf32, #blocked5>
    %30 = triton_gpu.convert_layout %29 : (tensor<32x32xf32, #blocked5>) -> tensor<32x32xf32, #blocked>
    %31:2 = "tt.reduce"(%30, %11) <{axis = 1 : i32}> ({
    ^bb0(%arg3: f32, %arg4: i32, %arg5: f32, %arg6: i32):
      %37 = "triton_gpu.cmpf"(%arg3, %arg5) <{predicate = 1 : i64}> : (f32, f32) -> i1
      %38 = "triton_gpu.cmpi"(%arg4, %arg6) <{predicate = 2 : i64}> : (i32, i32) -> i1
      %39 = arith.andi %37, %38 : i1
      %40 = "triton_gpu.cmpf"(%arg3, %arg5) <{predicate = 2 : i64}> : (f32, f32) -> i1
      %41 = arith.ori %40, %39 : i1
      %42 = arith.select %41, %arg3, %arg5 : f32
      %43 = arith.select %41, %arg4, %arg6 : i32
      tt.reduce.return %42, %43 : f32, i32
    }) : (tensor<32x32xf32, #blocked>, tensor<32x32xi32, #blocked>) -> (tensor<32xf32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>, tensor<32xi32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>)
    %32 = triton_gpu.convert_layout %31#1 : (tensor<32xi32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>) -> tensor<32xi32, #blocked1>
    %33 = tt.splat %arg2 : (!tt.ptr<i32>) -> tensor<32x!tt.ptr<i32>, #blocked1>
    %34 = tt.addptr %33, %0 : tensor<32x!tt.ptr<i32>, #blocked1>, tensor<32xi32, #blocked1>
    %35 = triton_gpu.convert_layout %34 : (tensor<32x!tt.ptr<i32>, #blocked1>) -> tensor<32x!tt.ptr<i32>, #blocked1>
    %36 = triton_gpu.convert_layout %32 : (tensor<32xi32, #blocked1>) -> tensor<32xi32, #blocked1>
    tt.store %35, %36 {cache = 1 : i32, evict = 1 : i32} : tensor<32xi32, #blocked1>
    tt.return
  }
}


// -----

// Check that we don't have extra convert for flash attention IR.
#blocked = #triton_gpu.blocked<{sizePerThread = [4, 4], threadsPerWarp = [2, 16], warpsPerCTA = [4, 1], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
#blocked2 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [4, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
#blocked3 = #triton_gpu.blocked<{sizePerThread = [1, 8], threadsPerWarp = [4, 8], warpsPerCTA = [4, 1], order = [1, 0], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
#blocked4 = #triton_gpu.blocked<{sizePerThread = [1, 1, 8], threadsPerWarp = [4, 1, 8], warpsPerCTA = [4, 1, 1], order = [1, 2, 0], CTAsPerCGA = [1, 1, 1], CTASplitNum = [1, 1, 1], CTAOrder = [1, 0, 2]}>
#blocked5 = #triton_gpu.blocked<{sizePerThread = [1, 1, 8], threadsPerWarp = [1, 4, 8], warpsPerCTA = [1, 4, 1], order = [0, 2, 1], CTAsPerCGA = [1, 1, 1], CTASplitNum = [1, 1, 1], CTAOrder = [0, 1, 2]}>
#blocked6 = #triton_gpu.blocked<{sizePerThread = [8, 1], threadsPerWarp = [8, 4], warpsPerCTA = [1, 4], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
#blocked7 = #triton_gpu.blocked<{sizePerThread = [8, 1, 1], threadsPerWarp = [8, 1, 4], warpsPerCTA = [1, 1, 4], order = [1, 0, 2], CTAsPerCGA = [1, 1, 1], CTASplitNum = [1, 1, 1], CTAOrder = [1, 0, 2]}>
#blocked8 = #triton_gpu.blocked<{sizePerThread = [1, 8, 1], threadsPerWarp = [1, 8, 4], warpsPerCTA = [1, 1, 4], order = [0, 1, 2], CTAsPerCGA = [1, 1, 1], CTASplitNum = [1, 1, 1], CTAOrder = [0, 1, 2]}>
#blocked9 = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [32, 1], warpsPerCTA = [4, 1], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [1, 0]}>
module attributes {"triton_gpu.compute-capability" = 90 : i32, "triton_gpu.num-ctas" = 1 : i32, "triton_gpu.num-warps" = 4 : i32, "triton_gpu.threads-per-warp" = 32 : i32} {
  tt.func public @attention_fw(%arg0: !tt.ptr<f16, 1> {tt.divisibility = 16 : i32}, %arg1: !tt.ptr<f16, 1> {tt.divisibility = 16 : i32}, %arg2: !tt.ptr<f16, 1> {tt.divisibility = 16 : i32}, %arg3: f32, %arg4: !tt.ptr<f32, 1> {tt.divisibility = 16 : i32}, %arg5: !tt.ptr<f16, 1> {tt.divisibility = 16 : i32}, %arg6: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg7: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg8: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg9: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg10: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg11: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg12: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg13: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg14: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg15: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg16: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg17: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg18: i32, %arg19: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg20: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}, %arg21: i32 {tt.divisibility = 16 : i32, tt.max_divisibility = 8 : i32}) attributes {noinline = false} {
    %c0_i64 = arith.constant 0 : i64
    %c64_i64 = arith.constant 64 : i64
    %cst = arith.constant dense<0.000000e+00> : tensor<128x64xf16, #blocked>
    %cst_0 = arith.constant dense<0xFF800000> : tensor<128xf32, #blocked1>
    %cst_1 = arith.constant dense<0.000000e+00> : tensor<128xf32, #blocked1>
    %c64_i32 = arith.constant 64 : i32
    %c0_i32 = arith.constant 0 : i32
    %cst_2 = arith.constant dense<0.000000e+00> : tensor<128x64xf32, #blocked2>
    %cst_3 = arith.constant 1.44269502 : f32
    %c128_i32 = arith.constant 128 : i32
    %0 = tt.get_program_id x : i32
    %1 = tt.get_program_id y : i32
    %2 = arith.muli %1, %arg7 : i32
    %3 = arith.muli %1, %arg10 : i32
    %4 = tt.addptr %arg0, %2 : !tt.ptr<f16, 1>, i32
    %5 = arith.muli %0, %c128_i32 : i32
    %6 = arith.extsi %arg8 : i32 to i64
    %7 = arith.extsi %5 : i32 to i64
    %8 = tt.addptr %arg1, %3 : !tt.ptr<f16, 1>, i32
    %9 = arith.addi %arg20, %arg21 : i32
    %10 = arith.extsi %arg11 : i32 to i64
    %11 = tt.addptr %arg2, %3 : !tt.ptr<f16, 1>, i32
    %12 = arith.extsi %arg14 : i32 to i64
    %13 = tt.make_range {end = 128 : i32, start = 0 : i32} : tensor<128xi32, #blocked1>
    %14 = tt.splat %5 : (i32) -> tensor<128xi32, #blocked1>
    %15 = arith.addi %14, %13 : tensor<128xi32, #blocked1>
    %16 = arith.mulf %arg3, %cst_3 : f32
    %17 = tt.splat %4 : (!tt.ptr<f16, 1>) -> tensor<128x64x!tt.ptr<f16, 1>, #blocked3>
    %18 = tt.splat %7 : (i64) -> tensor<128xi64, #blocked3>
    %19 = tt.make_range {end = 128 : i32, start = 0 : i32} : tensor<128xi32, #blocked3>
    %20 = arith.extsi %19 : tensor<128xi32, #blocked3> to tensor<128xi64, #blocked3>
    %21 = arith.addi %18, %20 : tensor<128xi64, #blocked3>
    %22 = triton_gpu.convert_layout %21 : (tensor<128xi64, #blocked3>) -> tensor<128xi64, #triton_gpu.slice<{dim = 1, parent = #blocked4}>>
    %23 = tt.expand_dims %22 {axis = 1 : i32} : (tensor<128xi64, #triton_gpu.slice<{dim = 1, parent = #blocked4}>>) -> tensor<128x1xi64, #blocked4>
    %24 = tt.splat %6 : (i64) -> tensor<128x1xi64, #blocked4>
    %25 = arith.muli %23, %24 : tensor<128x1xi64, #blocked4>
    %26 = tt.broadcast %25 : (tensor<128x1xi64, #blocked4>) -> tensor<128x64xi64, #blocked4>
    %27 = triton_gpu.convert_layout %26 : (tensor<128x64xi64, #blocked4>) -> tensor<128x64xi64, #blocked3>
    %28 = tt.addptr %17, %27 : tensor<128x64x!tt.ptr<f16, 1>, #blocked3>, tensor<128x64xi64, #blocked3>
    %29 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #blocked3>
    %30 = arith.extsi %29 : tensor<64xi32, #blocked3> to tensor<64xi64, #blocked3>
    %31 = triton_gpu.convert_layout %30 : (tensor<64xi64, #blocked3>) -> tensor<64xi64, #triton_gpu.slice<{dim = 0, parent = #blocked5}>>
    %32 = tt.expand_dims %31 {axis = 0 : i32} : (tensor<64xi64, #triton_gpu.slice<{dim = 0, parent = #blocked5}>>) -> tensor<1x64xi64, #blocked5>
    %33 = tt.broadcast %32 : (tensor<1x64xi64, #blocked5>) -> tensor<128x64xi64, #blocked5>
    %34 = triton_gpu.convert_layout %33 : (tensor<128x64xi64, #blocked5>) -> tensor<128x64xi64, #blocked3>
    %35 = tt.addptr %28, %34 : tensor<128x64x!tt.ptr<f16, 1>, #blocked3>, tensor<128x64xi64, #blocked3>
    %36 = tt.load %35 {boundaryCheck = array<i32>, cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<128x64xf16, #blocked3>
    %37 = triton_gpu.convert_layout %36 : (tensor<128x64xf16, #blocked3>) -> tensor<128x64xf16, #blocked2>
    %38 = tt.splat %16 : (f32) -> tensor<128x64xf32, #blocked2>
    %39 = arith.extf %37 : tensor<128x64xf16, #blocked2> to tensor<128x64xf32, #blocked2>
    %40 = arith.mulf %39, %38 : tensor<128x64xf32, #blocked2>
    %41 = arith.truncf %40 : tensor<128x64xf32, #blocked2> to tensor<128x64xf16, #blocked2>
// CHECK-NOT: triton_gpu.convert_layout
//     CHECK: scf.for
// CHECK-NOT:   triton_gpu.convert_layout
//     CHECK:   triton_gpu.convert_layout %{{.*}} #triton_gpu.dot_op
//     CHECK:   triton_gpu.convert_layout %{{.*}} #triton_gpu.dot_op
// CHECK-NOT:   triton_gpu.convert_layout
//     CHECK:   tt.dot
// CHECK-NOT:   triton_gpu.convert_layout
//     CHECK:   triton_gpu.convert_layout %{{.*}} #triton_gpu.dot_op
//     CHECK:   triton_gpu.convert_layout %{{.*}} #triton_gpu.dot_op
// CHECK-NOT:   triton_gpu.convert_layout
//     CHECK:   tt.dot
//     CHECK:   scf.yield
    %42:5 = scf.for %arg22 = %c0_i32 to %9 step %c64_i32 iter_args(%arg23 = %cst_2, %arg24 = %cst_1, %arg25 = %cst_0, %arg26 = %c0_i64, %arg27 = %c0_i64) -> (tensor<128x64xf32, #blocked2>, tensor<128xf32, #blocked1>, tensor<128xf32, #blocked1>, i64, i64)  : i32 {
      %78 = tt.splat %8 : (!tt.ptr<f16, 1>) -> tensor<64x64x!tt.ptr<f16, 1>, #blocked6>
      %79 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #blocked6>
      %80 = arith.extsi %79 : tensor<64xi32, #blocked6> to tensor<64xi64, #blocked6>
      %81 = triton_gpu.convert_layout %80 : (tensor<64xi64, #blocked6>) -> tensor<64xi64, #triton_gpu.slice<{dim = 1, parent = #blocked7}>>
      %82 = tt.expand_dims %81 {axis = 1 : i32} : (tensor<64xi64, #triton_gpu.slice<{dim = 1, parent = #blocked7}>>) -> tensor<64x1xi64, #blocked7>
      %83 = tt.broadcast %82 : (tensor<64x1xi64, #blocked7>) -> tensor<64x64xi64, #blocked7>
      %84 = triton_gpu.convert_layout %83 : (tensor<64x64xi64, #blocked7>) -> tensor<64x64xi64, #blocked6>
      %85 = tt.addptr %78, %84 : tensor<64x64x!tt.ptr<f16, 1>, #blocked6>, tensor<64x64xi64, #blocked6>
      %86 = tt.splat %arg26 : (i64) -> tensor<64xi64, #blocked6>
      %87 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #blocked6>
      %88 = arith.extsi %87 : tensor<64xi32, #blocked6> to tensor<64xi64, #blocked6>
      %89 = arith.addi %86, %88 : tensor<64xi64, #blocked6>
      %90 = triton_gpu.convert_layout %89 : (tensor<64xi64, #blocked6>) -> tensor<64xi64, #triton_gpu.slice<{dim = 0, parent = #blocked8}>>
      %91 = tt.expand_dims %90 {axis = 0 : i32} : (tensor<64xi64, #triton_gpu.slice<{dim = 0, parent = #blocked8}>>) -> tensor<1x64xi64, #blocked8>
      %92 = tt.splat %10 : (i64) -> tensor<1x64xi64, #blocked8>
      %93 = arith.muli %91, %92 : tensor<1x64xi64, #blocked8>
      %94 = tt.broadcast %93 : (tensor<1x64xi64, #blocked8>) -> tensor<64x64xi64, #blocked8>
      %95 = triton_gpu.convert_layout %94 : (tensor<64x64xi64, #blocked8>) -> tensor<64x64xi64, #blocked6>
      %96 = tt.addptr %85, %95 : tensor<64x64x!tt.ptr<f16, 1>, #blocked6>, tensor<64x64xi64, #blocked6>
      %97 = tt.load %96 {boundaryCheck = array<i32>, cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<64x64xf16, #blocked6>
      %98 = tt.splat %11 : (!tt.ptr<f16, 1>) -> tensor<64x64x!tt.ptr<f16, 1>, #blocked3>
      %99 = tt.splat %arg27 : (i64) -> tensor<64xi64, #blocked3>
      %100 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #blocked3>
      %101 = arith.extsi %100 : tensor<64xi32, #blocked3> to tensor<64xi64, #blocked3>
      %102 = arith.addi %99, %101 : tensor<64xi64, #blocked3>
      %103 = triton_gpu.convert_layout %102 : (tensor<64xi64, #blocked3>) -> tensor<64xi64, #triton_gpu.slice<{dim = 1, parent = #blocked4}>>
      %104 = tt.expand_dims %103 {axis = 1 : i32} : (tensor<64xi64, #triton_gpu.slice<{dim = 1, parent = #blocked4}>>) -> tensor<64x1xi64, #blocked4>
      %105 = tt.splat %12 : (i64) -> tensor<64x1xi64, #blocked4>
      %106 = arith.muli %104, %105 : tensor<64x1xi64, #blocked4>
      %107 = tt.broadcast %106 : (tensor<64x1xi64, #blocked4>) -> tensor<64x64xi64, #blocked4>
      %108 = triton_gpu.convert_layout %107 : (tensor<64x64xi64, #blocked4>) -> tensor<64x64xi64, #blocked3>
      %109 = tt.addptr %98, %108 : tensor<64x64x!tt.ptr<f16, 1>, #blocked3>, tensor<64x64xi64, #blocked3>
      %110 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #blocked3>
      %111 = arith.extsi %110 : tensor<64xi32, #blocked3> to tensor<64xi64, #blocked3>
      %112 = triton_gpu.convert_layout %111 : (tensor<64xi64, #blocked3>) -> tensor<64xi64, #triton_gpu.slice<{dim = 0, parent = #blocked5}>>
      %113 = tt.expand_dims %112 {axis = 0 : i32} : (tensor<64xi64, #triton_gpu.slice<{dim = 0, parent = #blocked5}>>) -> tensor<1x64xi64, #blocked5>
      %114 = tt.broadcast %113 : (tensor<1x64xi64, #blocked5>) -> tensor<64x64xi64, #blocked5>
      %115 = triton_gpu.convert_layout %114 : (tensor<64x64xi64, #blocked5>) -> tensor<64x64xi64, #blocked3>
      %116 = tt.addptr %109, %115 : tensor<64x64x!tt.ptr<f16, 1>, #blocked3>, tensor<64x64xi64, #blocked3>
      %117 = tt.load %116 {boundaryCheck = array<i32>, cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<64x64xf16, #blocked3>
      %118 = triton_gpu.convert_layout %41 : (tensor<128x64xf16, #blocked2>) -> tensor<128x64xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #blocked}>>
      %119 = triton_gpu.convert_layout %97 : (tensor<64x64xf16, #blocked6>) -> tensor<64x64xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #blocked}>>
      %120 = tt.dot %118, %119, %cst {allowTF32 = true, maxNumImpreciseAcc = 0 : i32} : tensor<128x64xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #blocked}>> * tensor<64x64xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #blocked}>> -> tensor<128x64xf16, #blocked>
      %121 = triton_gpu.convert_layout %120 : (tensor<128x64xf16, #blocked>) -> tensor<128x64xf16, #blocked2>
      %122 = arith.extf %121 : tensor<128x64xf16, #blocked2> to tensor<128x64xf32, #blocked2>
      %123 = "tt.reduce"(%122) <{axis = 1 : i32}> ({
      ^bb0(%arg28: f32, %arg29: f32):
        %153 = arith.maximumf %arg28, %arg29 : f32
        tt.reduce.return %153 : f32
      }) : (tensor<128x64xf32, #blocked2>) -> tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
      %124 = triton_gpu.convert_layout %123 : (tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<128xf32, #blocked1>
      %125 = arith.maximumf %arg25, %124 : tensor<128xf32, #blocked1>
      %126 = arith.subf %arg25, %125 : tensor<128xf32, #blocked1>
      %127 = tt.extern_elementwise %126 {pure = true, libname = "libdevice", libpath = "/root/.pyenv/versions/3.9.9/lib/python3.9/site-packages/triton/language/../third_party/cuda/lib/libdevice.10.bc", symbol = "__nv_exp2f"} : (tensor<128xf32, #blocked1>) -> tensor<128xf32, #blocked1>
      %128 = triton_gpu.convert_layout %125 : (tensor<128xf32, #blocked1>) -> tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked9}>>
      %129 = tt.expand_dims %128 {axis = 1 : i32} : (tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked9}>>) -> tensor<128x1xf32, #blocked9>
      %130 = triton_gpu.convert_layout %129 : (tensor<128x1xf32, #blocked9>) -> tensor<128x1xf32, #blocked2>
      %131 = tt.broadcast %130 : (tensor<128x1xf32, #blocked2>) -> tensor<128x64xf32, #blocked2>
      %132 = arith.subf %122, %131 : tensor<128x64xf32, #blocked2>
      %133 = tt.extern_elementwise %132 {pure = true, libname = "libdevice", libpath = "/root/.pyenv/versions/3.9.9/lib/python3.9/site-packages/triton/language/../third_party/cuda/lib/libdevice.10.bc", symbol = "__nv_exp2f"} : (tensor<128x64xf32, #blocked2>) -> tensor<128x64xf32, #blocked2>
      %134 = arith.mulf %arg24, %cst_1 : tensor<128xf32, #blocked1>
      %135 = arith.addf %134, %127 : tensor<128xf32, #blocked1>
      %136 = triton_gpu.convert_layout %135 : (tensor<128xf32, #blocked1>) -> tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked9}>>
      %137 = tt.expand_dims %136 {axis = 1 : i32} : (tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked9}>>) -> tensor<128x1xf32, #blocked9>
      %138 = triton_gpu.convert_layout %137 : (tensor<128x1xf32, #blocked9>) -> tensor<128x1xf32, #blocked2>
      %139 = tt.broadcast %138 : (tensor<128x1xf32, #blocked2>) -> tensor<128x64xf32, #blocked2>
      %140 = arith.mulf %arg23, %139 : tensor<128x64xf32, #blocked2>
      %141 = arith.truncf %133 : tensor<128x64xf32, #blocked2> to tensor<128x64xf16, #blocked2>
      %142 = triton_gpu.convert_layout %141 : (tensor<128x64xf16, #blocked2>) -> tensor<128x64xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #blocked}>>
      %143 = triton_gpu.convert_layout %117 : (tensor<64x64xf16, #blocked3>) -> tensor<64x64xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #blocked}>>
      %144 = triton_gpu.convert_layout %140 : (tensor<128x64xf32, #blocked2>) -> tensor<128x64xf32, #blocked>
      %145 = tt.dot %142, %143, %144 {allowTF32 = true, maxNumImpreciseAcc = 0 : i32} : tensor<128x64xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #blocked}>> * tensor<64x64xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #blocked}>> -> tensor<128x64xf32, #blocked>
      %146 = triton_gpu.convert_layout %145 : (tensor<128x64xf32, #blocked>) -> tensor<128x64xf32, #blocked2>
      %147 = arith.mulf %arg24, %127 : tensor<128xf32, #blocked1>
      %148 = "tt.reduce"(%133) <{axis = 1 : i32}> ({
      ^bb0(%arg28: f32, %arg29: f32):
        %153 = arith.addf %arg28, %arg29 : f32
        tt.reduce.return %153 : f32
      }) : (tensor<128x64xf32, #blocked2>) -> tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>
      %149 = triton_gpu.convert_layout %148 : (tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked2}>>) -> tensor<128xf32, #blocked1>
      %150 = arith.addf %147, %149 : tensor<128xf32, #blocked1>
      %151 = arith.addi %arg26, %c64_i64 : i64
      %152 = arith.addi %arg27, %c64_i64 : i64
      scf.yield %146, %150, %125, %151, %152 : tensor<128x64xf32, #blocked2>, tensor<128xf32, #blocked1>, tensor<128xf32, #blocked1>, i64, i64
    }
    %43 = triton_gpu.convert_layout %42#1 : (tensor<128xf32, #blocked1>) -> tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked9}>>
    %44 = tt.expand_dims %43 {axis = 1 : i32} : (tensor<128xf32, #triton_gpu.slice<{dim = 1, parent = #blocked9}>>) -> tensor<128x1xf32, #blocked9>
    %45 = triton_gpu.convert_layout %44 : (tensor<128x1xf32, #blocked9>) -> tensor<128x1xf32, #blocked2>
    %46 = tt.broadcast %45 : (tensor<128x1xf32, #blocked2>) -> tensor<128x64xf32, #blocked2>
    %47 = arith.divf %42#0, %46 : tensor<128x64xf32, #blocked2>
    %48 = arith.muli %1, %arg20 : i32
    %49 = tt.addptr %arg4, %48 : !tt.ptr<f32, 1>, i32
    %50 = tt.splat %49 : (!tt.ptr<f32, 1>) -> tensor<128x!tt.ptr<f32, 1>, #blocked1>
    %51 = tt.addptr %50, %15 : tensor<128x!tt.ptr<f32, 1>, #blocked1>, tensor<128xi32, #blocked1>
    %52 = tt.extern_elementwise %42#1 {pure = true, libname = "libdevice", libpath = "/root/.pyenv/versions/3.9.9/lib/python3.9/site-packages/triton/language/../third_party/cuda/lib/libdevice.10.bc", symbol = "__nv_log2f"} : (tensor<128xf32, #blocked1>) -> tensor<128xf32, #blocked1>
    %53 = arith.addf %42#2, %52 : tensor<128xf32, #blocked1>
    tt.store %51, %53 {cache = 1 : i32, evict = 1 : i32} : tensor<128xf32, #blocked1>
    %54 = tt.addptr %arg5, %2 : !tt.ptr<f16, 1>, i32
    %55 = arith.extsi %arg17 : i32 to i64
    %56 = arith.extsi %5 : i32 to i64
    %57 = arith.truncf %47 : tensor<128x64xf32, #blocked2> to tensor<128x64xf16, #blocked2>
    %58 = triton_gpu.convert_layout %57 : (tensor<128x64xf16, #blocked2>) -> tensor<128x64xf16, #blocked3>
    %59 = tt.splat %54 : (!tt.ptr<f16, 1>) -> tensor<128x64x!tt.ptr<f16, 1>, #blocked3>
    %60 = tt.splat %56 : (i64) -> tensor<128xi64, #blocked3>
    %61 = tt.make_range {end = 128 : i32, start = 0 : i32} : tensor<128xi32, #blocked3>
    %62 = arith.extsi %61 : tensor<128xi32, #blocked3> to tensor<128xi64, #blocked3>
    %63 = arith.addi %60, %62 : tensor<128xi64, #blocked3>
    %64 = triton_gpu.convert_layout %63 : (tensor<128xi64, #blocked3>) -> tensor<128xi64, #triton_gpu.slice<{dim = 1, parent = #blocked4}>>
    %65 = tt.expand_dims %64 {axis = 1 : i32} : (tensor<128xi64, #triton_gpu.slice<{dim = 1, parent = #blocked4}>>) -> tensor<128x1xi64, #blocked4>
    %66 = tt.splat %55 : (i64) -> tensor<128x1xi64, #blocked4>
    %67 = arith.muli %65, %66 : tensor<128x1xi64, #blocked4>
    %68 = tt.broadcast %67 : (tensor<128x1xi64, #blocked4>) -> tensor<128x64xi64, #blocked4>
    %69 = triton_gpu.convert_layout %68 : (tensor<128x64xi64, #blocked4>) -> tensor<128x64xi64, #blocked3>
    %70 = tt.addptr %59, %69 : tensor<128x64x!tt.ptr<f16, 1>, #blocked3>, tensor<128x64xi64, #blocked3>
    %71 = tt.make_range {end = 64 : i32, start = 0 : i32} : tensor<64xi32, #blocked3>
    %72 = arith.extsi %71 : tensor<64xi32, #blocked3> to tensor<64xi64, #blocked3>
    %73 = triton_gpu.convert_layout %72 : (tensor<64xi64, #blocked3>) -> tensor<64xi64, #triton_gpu.slice<{dim = 0, parent = #blocked5}>>
    %74 = tt.expand_dims %73 {axis = 0 : i32} : (tensor<64xi64, #triton_gpu.slice<{dim = 0, parent = #blocked5}>>) -> tensor<1x64xi64, #blocked5>
    %75 = tt.broadcast %74 : (tensor<1x64xi64, #blocked5>) -> tensor<128x64xi64, #blocked5>
    %76 = triton_gpu.convert_layout %75 : (tensor<128x64xi64, #blocked5>) -> tensor<128x64xi64, #blocked3>
    %77 = tt.addptr %70, %76 : tensor<128x64x!tt.ptr<f16, 1>, #blocked3>, tensor<128x64xi64, #blocked3>
    tt.store %77, %58 {cache = 1 : i32, evict = 1 : i32} : tensor<128x64xf16, #blocked3>
    tt.return
  }
}

// -----

#blocked = #triton_gpu.blocked<{sizePerThread = [1, 1], threadsPerWarp = [1, 32], warpsPerCTA = [1, 4], order = [0, 1], CTAsPerCGA = [1, 1], CTASplitNum = [1, 1], CTAOrder = [0, 1]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
// CHECK-LABEL: axis_mismatch
tt.func @axis_mismatch(%arg0: f32) -> tensor<1xf32, #triton_gpu.slice<{dim = 0, parent = #blocked}>> {
// CHECK: %[[R:.+]] = "tt.reduce"(%0) <{axis = 1 : i32}>
// CHECK: %[[C:.+]] = triton_gpu.convert_layout %[[R]]
// CHECK: tt.return %[[C]]
  %0 = tt.splat %arg0 : (f32) -> tensor<1x16xf32, #blocked>
  %1 = "tt.reduce"(%0) <{axis = 1 : i32}> ({
    ^bb0(%arg9: f32, %arg10: f32):
    %60 = arith.addf %arg9, %arg10 : f32
    tt.reduce.return %60 : f32
  }) : (tensor<1x16xf32, #blocked>) -> tensor<1xf32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>
  %2 = triton_gpu.convert_layout %1 : (tensor<1xf32, #triton_gpu.slice<{dim = 1, parent = #blocked}>>) -> tensor<1xf32, #blocked1>
  %3 = triton_gpu.convert_layout %2 : (tensor<1xf32, #blocked1>) -> tensor<1xf32, #triton_gpu.slice<{dim = 0, parent = #blocked}>>
  tt.return %3: tensor<1xf32, #triton_gpu.slice<{dim = 0, parent = #blocked}>>
}

// -----

#blocked = #triton_gpu.blocked<{sizePerThread = [4], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
module attributes {"triton_gpu.num-warps" = 4 : i32} {
// CHECK-LABEL: reduce_to_scalar
//   CHECK-NOT:   triton_gpu.convert_layout
//       CHECK:   tt.return
tt.func @reduce_to_scalar(%ptr: tensor<1024x!tt.ptr<f32>, #blocked>) -> (f32, i32) {
  %0 = tt.load %ptr {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked>
  %1 = triton_gpu.convert_layout %0 : (tensor<1024xf32, #blocked>) -> tensor<1024xf32, #blocked1>
  %2 = tt.make_range {end = 1024 : i32, start = 0 : i32} : tensor<1024xi32, #blocked1>
  %3:2 = "tt.reduce"(%1, %2) <{axis = 0 : i32}> ({
    ^bb0(%arg7: f32, %arg8: i32, %arg9: f32, %arg10: i32):
    %51 = "triton_gpu.cmpf"(%arg7, %arg9) <{predicate = 1 : i64}> : (f32, f32) -> i1
    %52 = "triton_gpu.cmpi"(%arg8, %arg10) <{predicate = 2 : i64}> : (i32, i32) -> i1
    %53 = arith.andi %51, %52 : i1
    %54 = "triton_gpu.cmpf"(%arg7, %arg9) <{predicate = 2 : i64}> : (f32, f32) -> i1
    %55 = arith.ori %54, %53 : i1
    %56 = arith.select %55, %arg7, %arg9 : f32
    %57 = arith.select %55, %arg8, %arg10 : i32
    tt.reduce.return %56, %57 : f32, i32
  }) : (tensor<1024xf32, #blocked1>, tensor<1024xi32, #blocked1>) -> (f32, i32)
  tt.return %3#0, %3#1: f32, i32
}
}

// -----

#blocked = #triton_gpu.blocked<{sizePerThread = [4], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
#blocked1 = #triton_gpu.blocked<{sizePerThread = [1], threadsPerWarp = [32], warpsPerCTA = [4], order = [0], CTAsPerCGA = [1], CTASplitNum = [1], CTAOrder = [0]}>
module attributes {"triton_gpu.num-warps" = 4 : i32} {
// CHECK-LABEL: whileop
//       CHECK: %[[L:.+]] = tt.load %{{.*}} {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked>
//       CHECK: %[[W:.+]] = scf.while (%[[I:.+]] = %[[L]], %{{.*}} = %{{.*}}) : (tensor<1024xf32, #blocked>, i1) -> tensor<1024xf32, #blocked> {
//       CHECK:   scf.condition(%{{.*}}) %[[I]] : tensor<1024xf32, #blocked>
//       CHECK: } do {
//       CHECK: ^bb0(%[[ARG1:.+]]: tensor<1024xf32, #blocked>):
//       CHECK:    %[[ADD:.+]] = arith.addf %[[ARG1]], %[[ARG1]] : tensor<1024xf32, #blocked>
//       CHECK:    scf.yield %[[ADD]], %{{.*}} : tensor<1024xf32, #blocked>, i1
//       CHECK:  }
//       CHECK:  tt.store %{{.*}}, %[[W]] {cache = 1 : i32, evict = 1 : i32} : tensor<1024xf32, #blocked>
tt.func @whileop(%ptr: tensor<1024x!tt.ptr<f32>, #blocked>, %cond: i1) {
  %0 = tt.load %ptr {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<1024xf32, #blocked>
  %1 = triton_gpu.convert_layout %0 : (tensor<1024xf32, #blocked>) -> tensor<1024xf32, #blocked1>
  %2 = scf.while (%arg0 = %1, %arg1 = %cond) : (tensor<1024xf32, #blocked1>, i1) -> (tensor<1024xf32, #blocked1>) {
      scf.condition(%arg1) %arg0 : tensor<1024xf32, #blocked1>
    } do {
    ^bb0(%arg0: tensor<1024xf32, #blocked1>):
      %4 = triton_gpu.convert_layout %arg0 : (tensor<1024xf32, #blocked1>) -> tensor<1024xf32, #blocked>
      %5 = arith.addf %4, %4 : tensor<1024xf32, #blocked>
      %6 = triton_gpu.convert_layout %5 : (tensor<1024xf32, #blocked>) -> tensor<1024xf32, #blocked1>
      scf.yield %6, %cond : tensor<1024xf32, #blocked1>, i1
    }
  %3 = triton_gpu.convert_layout %2 : (tensor<1024xf32, #blocked1>) -> tensor<1024xf32, #blocked>
  tt.store %ptr, %3 {cache = 1 : i32, evict = 1 : i32} : tensor<1024xf32, #blocked>
  tt.return
}
}
