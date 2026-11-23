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
	andl	$7, %r8d
	cmpq	$7, %rcx
	jae	.LBB0_8
# %bb.3:
	vxorps	%xmm0, %xmm0, %xmm0
	xorl	%ecx, %ecx
	jmp	.LBB0_4
.LBB0_1:
	vxorps	%xmm0, %xmm0, %xmm0
	vmovss	%xmm0, (%rdx)
	retq
.LBB0_8:
	andl	$-8, %eax
	vxorps	%xmm0, %xmm0, %xmm0
	xorl	%ecx, %ecx
	.p2align	4, 0x90
.LBB0_9:                                # =>This Inner Loop Header: Depth=1
	vmovss	(%rdi,%rcx,4), %xmm1            # xmm1 = mem[0],zero,zero,zero
	vmovss	4(%rdi,%rcx,4), %xmm2           # xmm2 = mem[0],zero,zero,zero
	vsubss	(%rsi,%rcx,4), %xmm1, %xmm1
	vfmadd213ss	%xmm0, %xmm1, %xmm1     # xmm1 = (xmm1 * xmm1) + xmm0
	vsubss	4(%rsi,%rcx,4), %xmm2, %xmm0
	vfmadd213ss	%xmm1, %xmm0, %xmm0     # xmm0 = (xmm0 * xmm0) + xmm1
	vmovss	8(%rdi,%rcx,4), %xmm1           # xmm1 = mem[0],zero,zero,zero
	vsubss	8(%rsi,%rcx,4), %xmm1, %xmm1
	vmovss	12(%rdi,%rcx,4), %xmm2          # xmm2 = mem[0],zero,zero,zero
	vsubss	12(%rsi,%rcx,4), %xmm2, %xmm2
	vfmadd213ss	%xmm0, %xmm1, %xmm1     # xmm1 = (xmm1 * xmm1) + xmm0
	vfmadd213ss	%xmm1, %xmm2, %xmm2     # xmm2 = (xmm2 * xmm2) + xmm1
	vmovss	16(%rdi,%rcx,4), %xmm0          # xmm0 = mem[0],zero,zero,zero
	vsubss	16(%rsi,%rcx,4), %xmm0, %xmm0
	vfmadd213ss	%xmm2, %xmm0, %xmm0     # xmm0 = (xmm0 * xmm0) + xmm2
	vmovss	20(%rdi,%rcx,4), %xmm1          # xmm1 = mem[0],zero,zero,zero
	vsubss	20(%rsi,%rcx,4), %xmm1, %xmm1
	vfmadd213ss	%xmm0, %xmm1, %xmm1     # xmm1 = (xmm1 * xmm1) + xmm0
	vmovss	24(%rdi,%rcx,4), %xmm0          # xmm0 = mem[0],zero,zero,zero
	vsubss	24(%rsi,%rcx,4), %xmm0, %xmm2
	vmovss	28(%rdi,%rcx,4), %xmm0          # xmm0 = mem[0],zero,zero,zero
	vfmadd213ss	%xmm1, %xmm2, %xmm2     # xmm2 = (xmm2 * xmm2) + xmm1
	vsubss	28(%rsi,%rcx,4), %xmm0, %xmm0
	vfmadd213ss	%xmm2, %xmm0, %xmm0     # xmm0 = (xmm0 * xmm0) + xmm2
	addq	$8, %rcx
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
	vmovss	(%rcx,%rsi,4), %xmm1            # xmm1 = mem[0],zero,zero,zero
	vsubss	(%rax,%rsi,4), %xmm1, %xmm1
	vfmadd231ss	%xmm1, %xmm1, %xmm0     # xmm0 = (xmm1 * xmm1) + xmm0
	incq	%rsi
	cmpq	%rsi, %r8
	jne	.LBB0_6
.LBB0_7:
	vmovss	%xmm0, (%rdx)
	retq
.Lfunc_end0:
	.size	l2_kernel, .Lfunc_end0-l2_kernel
                                        # -- End function
	.ident	"Ubuntu clang version 14.0.0-1ubuntu1.1"
	.section	".note.GNU-stack","",@progbits
	.addrsig
