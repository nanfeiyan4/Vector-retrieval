	.text
	.file	"l2kernel.c"
	.globl	l2_kernel                       # -- Begin function l2_kernel
	.p2align	4, 0x90
	.type	l2_kernel,@function
l2_kernel:                              # @l2_kernel
# %bb.0:
	testl	%ecx, %ecx
	jle	.LBB0_1
# %bb.2:
	movl	%ecx, %eax
	leaq	-1(%rax), %rcx
	movl	%eax, %r8d
	andl	$3, %r8d
	cmpq	$3, %rcx
	jae	.LBB0_8
# %bb.3:
	xorps	%xmm0, %xmm0
	xorl	%ecx, %ecx
	jmp	.LBB0_4
.LBB0_1:
	xorps	%xmm0, %xmm0
	movss	%xmm0, (%rdx)
	retq
.LBB0_8:
	andl	$-4, %eax
	xorps	%xmm0, %xmm0
	xorl	%ecx, %ecx
	.p2align	4, 0x90
.LBB0_9:                                # =>This Inner Loop Header: Depth=1
	movss	(%rdi,%rcx,4), %xmm1            # xmm1 = mem[0],zero,zero,zero
	movss	4(%rdi,%rcx,4), %xmm2           # xmm2 = mem[0],zero,zero,zero
	subss	(%rsi,%rcx,4), %xmm1
	mulss	%xmm1, %xmm1
	addss	%xmm0, %xmm1
	subss	4(%rsi,%rcx,4), %xmm2
	mulss	%xmm2, %xmm2
	addss	%xmm1, %xmm2
	movss	8(%rdi,%rcx,4), %xmm1           # xmm1 = mem[0],zero,zero,zero
	subss	8(%rsi,%rcx,4), %xmm1
	mulss	%xmm1, %xmm1
	addss	%xmm2, %xmm1
	movss	12(%rdi,%rcx,4), %xmm0          # xmm0 = mem[0],zero,zero,zero
	subss	12(%rsi,%rcx,4), %xmm0
	mulss	%xmm0, %xmm0
	addss	%xmm1, %xmm0
	addq	$4, %rcx
	cmpq	%rcx, %rax
	jne	.LBB0_9
.LBB0_4:
	testq	%r8, %r8
	je	.LBB0_7
# %bb.5:
	leaq	(%rsi,%rcx,4), %rax
	leaq	(%rdi,%rcx,4), %rcx
	xorl	%esi, %esi
	.p2align	4, 0x90
.LBB0_6:                                # =>This Inner Loop Header: Depth=1
	movss	(%rcx,%rsi,4), %xmm1            # xmm1 = mem[0],zero,zero,zero
	subss	(%rax,%rsi,4), %xmm1
	mulss	%xmm1, %xmm1
	addss	%xmm1, %xmm0
	addq	$1, %rsi
	cmpq	%rsi, %r8
	jne	.LBB0_6
.LBB0_7:
	movss	%xmm0, (%rdx)
	retq
.Lfunc_end0:
	.size	l2_kernel, .Lfunc_end0-l2_kernel
                                        # -- End function
	.ident	"Ubuntu clang version 14.0.0-1ubuntu1.1"
	.section	".note.GNU-stack","",@progbits
	.addrsig
