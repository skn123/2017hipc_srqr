!     RANDOMIZED QRCP ON MATRIX A
!     AUTHOR: JIANWEI XIAO AND JULIEN LANGOU

!     M: NUMBER OF ROWS OF A
!     N: NUMBER OF COLUMNS OF A
!     K: APPROXIMATE RANK
!     A: INPUT MATRIX A
!     DESC_A: DESCRIPTOR OF A
!     M_B: NUMBER OF ROWS OF B
!     N_B: NUMBER OF COLUMNS OF B
!     B: STORE OMEGA * A, COMPRESSION MATRIX
!     DESC_B: DESCRIPTOR OF B
!     OMEGA: RANDOM MATRIX 
!     DESC_OMEGA: DESCRIPTOR OF OMEGA
!     IPIV: COLUMN PIVOTING VECTOR OF A
!     TAU: COEFFICIENTS OF HOUSEHOLDER REFLECTIONS OF A
!     NB_MAX: USER DEFINED BLOCKSIZE
!     IPIV_B: PIVOTING VECTOR OF MATRIX B
!     TAU_B: COEFFICIENTS OF HOUSEHOLDER REFLECTIONS OF B
!     WORK: WORK ARRAY
!     LWORK: SIZE OF WORK ARRAY

! Reference: 
! Fast Parallel Randomized QR with Column Pivoting Algorithms for Reliable Low-rank Matrix Approximations.
! Jianwei Xiao, Ming Gu and Julien Langou.
! 24th IEEE International Conference on High Performance Computing, Data, and Analytics (HIPC), Jaipur, India, 2017.

SUBROUTINE RQRCP( M, N, K, A, DESC_A, M_B, N_B, B, DESC_B, OMEGA, DESC_OMEGA, IPIV, TAU, NB_MAX, &
      IPIV_B, TAU_B, WORK, LWORK )

IMPLICIT NONE

INTEGER            M, N, M_B, N_B, NB_MAX, K
INTEGER            DESC_A( * ), DESC_B( * ), DESC_OMEGA( * )
DOUBLE PRECISION   A( * ), OMEGA( * ), B( * )
INTEGER            IPIV( * ) ! NEEDS TO BE OF SIZE N
DOUBLE PRECISION   TAU( * )
INTEGER            IPIV_B( * )
DOUBLE PRECISION   TAU_B( * )
INTEGER            LWORK
DOUBLE PRECISION   WORK( * )

INTEGER            I, ICOL, NB, INFO, IN, J, ITEMP, ICTXT, IPW, NQ, NPCOL, NPROW, MYCOL, MYROW, IACOL, LLA
INTEGER            JN, KSTEP, IIA, JJA, IAROW, KSTART, KB, KK, JA, JB, IA, LL, LDA

INTEGER    BLOCK_CYCLIC_2D, CSRC_, CTXT_, DLEN_, DTYPE_, LLD_, MB_, M_, NB_, N_, RSRC_
PARAMETER  ( BLOCK_CYCLIC_2D = 1, DLEN_ = 9, DTYPE_ = 1, CTXT_ = 2, M_ = 3, N_ = 4, &
      MB_ = 5, NB_ = 6, RSRC_ = 7, CSRC_ = 8, LLD_ = 9 )

CHARACTER          COLBTOP, ROWBTOP

EXTERNAL           PDGEMM

INTEGER            INDXL2G, NUMROC
EXTERNAL           INDXL2G, NUMROC

INTEGER            ICEIL
INTRINSIC          MIN

DOUBLE PRECISION   PDLANGE, ANORM, MPIT1, MPIT2, MPIELAPSED, MPI_WTIME

DOUBLE PRECISION   TIME_PDGEMM, TIME_PARTIAL_QR, TIME_PANEL_QR, TIME_UPDATING_A, TIME_UPDATING_B

ICTXT = DESC_A( CTXT_ )
CALL BLACS_GRIDINFO( ICTXT, NPROW, NPCOL, MYROW, MYCOL )

CALL PB_TOPGET( ICTXT, 'BROADCAST', 'ROWWISE', ROWBTOP )
CALL PB_TOPGET( ICTXT, 'BROADCAST', 'COLUMNWISE', COLBTOP )
CALL PB_TOPSET( ICTXT, 'BROADCAST', 'ROWWISE', 'I-RING' )
CALL PB_TOPSET( ICTXT, 'BROADCAST', 'COLUMNWISE', ' ' )

IPW = DESC_A( NB_ ) * DESC_A( NB_ ) + 1
IA = 1
JA = 1

! COMPUTE B = OMEGA * A.
CALL PDGEMM( 'N', 'N', M_B, N_B, M, 1.0D+0, OMEGA, 1, 1, DESC_OMEGA, A, 1, 1, DESC_A, 0.0D+0, B, 1, 1, DESC_B )

!
!     INITIALIZE THE ARRAY OF PIVOTS
!
NQ = NUMROC( N, DESC_A( NB_ ), MYCOL, IACOL, NPCOL )
CALL INFOG2L( IA, JA, DESC_A, NPROW, NPCOL, MYROW, MYCOL, IIA, JJA, IAROW, IACOL )
LDA = DESC_A( LLD_ )
JN = MIN( ICEIL( JA, DESC_A( NB_ ) ) * DESC_A( NB_ ), N )
KSTEP  = NPCOL * DESC_A( NB_ )
!
IF( MYCOL.EQ.IACOL ) THEN
      !
      !        HANDLE FIRST BLOCK SEPARATELY
      !
      JB = JN - JA + 1
      DO LL = JJA, JJA+JB-1
            ITEMP = JA + LL - JJA
            IPIV( LL ) = ITEMP
            IPIV_B( LL ) = ITEMP
      END DO
      KSTART = JN + KSTEP - DESC_A( NB_ )
      !
      !        LOOP OVER REMAINING BLOCK OF COLUMNS
      !
      DO KK = JJA+JB, JJA+NQ-1, DESC_A( NB_ )
            KB = MIN( JJA+NQ-KK, DESC_A( NB_ ) )
            DO LL = KK, KK+KB-1
                  ITEMP = KSTART+LL-KK+1
                  IPIV( LL ) = ITEMP
                  IPIV_B( LL ) = ITEMP
            END DO
            KSTART = KSTART + KSTEP
      END DO
ELSE
      KSTART = JN + ( MOD( MYCOL-IACOL+NPCOL, NPCOL )-1 )*DESC_A( NB_ )
      DO KK = JJA, JJA+NQ-1, DESC_A( NB_ )
            KB = MIN( JJA+NQ-KK, DESC_A( NB_ ) )
            DO LL = KK, KK+KB-1
                  ITEMP = KSTART+LL-KK+1
                  IPIV( LL ) = ITEMP
                  IPIV_B( LL ) = ITEMP
            END DO
            KSTART = KSTART + KSTEP
      END DO
END IF

NB = NB_MAX
DO ICOL = 1, K, NB
      NB = MIN( K-ICOL+1, NB_MAX )
      ! DO PARTIAL QRCP ON B TO FIND NB PIVOTS, MEANWHILE DO SOME SWAPS ON A AND IPIV
      CALL PARTIAL_QR_SWAP( NB, M_B, N_B-ICOL+1, B, 1, ICOL, DESC_B, IPIV_B, TAU_B, WORK, LWORK, INFO, &
           M, DESC_A( LLD_ ), A, DESC_A, IPIV)

      ! DO QR ON LEADING COLUMNS IN TRAILING MATRIX OF A
      CALL PDGEQR2( M-ICOL+1, NB, A, ICOL, ICOL, DESC_A, TAU, WORK, LWORK, INFO )
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      ! APPLY A BLOCK OF HOUSEHOLDER REFLECTIONS TO REST COLUMNS
      ! THIS PART IS TIME CONSUMING
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      ! CALL PDORMQR( 'L', 'T', M-ICOL+1, N-ICOL+1-NB, NB, A, ICOL, ICOL, DESC_A, &
      !       TAU, A, ICOL, ICOL+NB, DESC_A, WORK, LWORK, INFO)

      ! THIS PART ASSUMES NB_DIST IS A MULTIPLE OF NB_ALG
      CALL PDLARFT( 'FORWARD', 'COLUMNWISE', M-ICOL+1, NB, A, ICOL, ICOL, DESC_A, TAU, &
            WORK, WORK( IPW ) )

      CALL PDLARFB( 'LEFT', 'TRANSPOSE', 'FORWARD', 'COLUMNWISE', M-ICOL+1, N-ICOL+1-NB, &
            NB, A, ICOL, ICOL, DESC_A, &
            WORK, A, ICOL, ICOL+NB, DESC_A, WORK( IPW ) )
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      ! UPDATE COMPRESSION MATRIX B
      IF (ICOL + NB < K + 1) THEN
            ! NEED FILL ZERO IN THE STRICTLY LOWER PART OF B(1:NB, ICOL:ICOL+NB-1)
            CALL PDLASET( 'L', NB-1, NB-1, 0.0D+0, 0.0D+0, B, 2, ICOL, DESC_B)
            ! STEP1: COMPUTE S11 <- S11R11^{-1}
            CALL PDTRSM('R', 'U', 'N', 'N', NB, NB, 1.0D+0, A, ICOL, ICOL, DESC_A, B, 1, ICOL, DESC_B)
            ! STEP2: COMPUTE S12 <- S12 - S11R12
            CALL PDGEMM( 'N', 'N', NB, N_B-ICOL-NB+1, NB, -1.0D+0, B, 1, ICOL, DESC_B, A, ICOL, &
                  ICOL+NB, DESC_A, 1.0D+0, B, 1, ICOL+NB, DESC_B)
            ! STEP3: S22 KEEP THE SAME
      ELSE
      END IF
END DO
CALL PB_TOPSET( ICTXT, 'BROADCAST', 'ROWWISE', ROWBTOP )
CALL PB_TOPSET( ICTXT, 'BROADCAST', 'COLUMNWISE', COLBTOP )
END
