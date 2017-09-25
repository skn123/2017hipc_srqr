!	M -- NUMBER OF ROWS IN A
!	N -- NUMBER OF COLUMNS IN A
!	K -- APPROXIMATE RANK K
!	NB_MAX -- USER DEFINED BLOCKSIZE
!	P -- OVERSAMPLINE, B_MAX + P IS THE NUMBER OF ROWS IN GAUSSIAN RANDOM MATRIX OMEGA
!   A -- INPUT MATRIX A
!	TAU -- THE SCALAR FACTORS OF THE ELEMENTARY REFLECTORS
!	IPIV -- PIVOTING VECTOR
!   G -- USER DEFINED TOLERANCE PARAMETER
!   D -- NUMBER OF ROWS OF THE RANDOM MATRIX USED IN THE EXTRA SWAPS STAGE
!	WORK -- WORKSPACE
!	LWORK -- SIZE OF WORKSPACE
!   NUM_SWAPS -- NUMBER OF SWAPS

!   UPPER_BOUND -- UPPER BOUND OF NUMBER OF EXTRA SWAPS
!   HOUSEHOLDER -- HOUSEHOLDER REFLECTORS FROM RQRCP
!   GIVENS_ARRAY -- THE DA, DB PARAMETERS IN THE GIVENS ROTATIONS IN THE EXTRA SWAPS STAGE
!   INDEX_ARRAY -- OMEGA_MAX_COL_INDEX IN THE EXTRA SWAPS STAGE
!   EXTRA_HOUSEHOLDER -- HOUSEHOLDER REFLECTORS IN FINDING ALPHA IN THE TRAILING MATRIX OF A
!   EXTRA_HOUSEHOLDER -- COEFFICIENT OF HOUSEHOLDER REFLECTORS IN FINDING ALPHA IN THE TRAILING MATRIX OF A

! Reference: 
! Fast Parallel Randomized QR with Column Pivoting Algorithms for Reliable Low-rank Matrix Approximations.
! Jianwei Xiao, Ming Gu and Julien Langou.
! 24th IEEE International Conference on High Performance Computing, Data, and Analytics (HIPC), Jaipur, India, 2017.

SUBROUTINE SRQR(M, N, K, NB_MAX, P, A, TAU, IPIV, G, D, WORK, LWORK, NUM_SWAPS, UPPER_BOUND, HOUSEHOLDER, GIVENS_ARRAY, &
	INDEX_ARRAY, EXTRA_HOUSEHOLDER, EXTRA_TAU)

INTEGER, INTENT(IN) :: M, N, K, NB_MAX, P, LWORK, D, UPPER_BOUND
DOUBLE PRECISION, INTENT(IN) :: G
DOUBLE PRECISION, INTENT(INOUT), DIMENSION(M,N) :: A
DOUBLE PRECISION, INTENT(OUT), DIMENSION(N) :: TAU
INTEGER, INTENT(OUT), DIMENSION(N) :: IPIV
DOUBLE PRECISION, INTENT(INOUT), DIMENSION(LWORK) :: WORK
INTEGER, INTENT(OUT) :: NUM_SWAPS
DOUBLE PRECISION, INTENT(OUT), DIMENSION(M,K+1) :: HOUSEHOLDER
DOUBLE PRECISION, INTENT(OUT), DIMENSION(K,UPPER_BOUND) :: GIVENS_ARRAY
INTEGER, INTENT(OUT), DIMENSION(UPPER_BOUND) :: INDEX_ARRAY
DOUBLE PRECISION, INTENT(OUT), DIMENSION(M-K,UPPER_BOUND) :: EXTRA_HOUSEHOLDER
DOUBLE PRECISION, INTENT(OUT), DIMENSION(UPPER_BOUND) :: EXTRA_TAU

DOUBLE PRECISION :: OMEGA_MAX_COL_NORM, OMEGA_CURR_COL_NORM, ALPHA, &
DLANGE, SQRT, DBLE, DA, DB, C, S
DOUBLE PRECISION, DIMENSION(:,:), ALLOCATABLE :: OMEGA_TEMP, B, OMEGA
DOUBLE PRECISION, DIMENSION(:), ALLOCATABLE :: TAU_B
DOUBLE PRECISION, DIMENSION(:), ALLOCATABLE :: TRAILING_COL_NORM
DOUBLE PRECISION :: TRAILING_MAX_COL_NORM, DTEMP
INTEGER :: TRAILING_MAX_COL_INDEX
INTEGER :: OMEGA_MAX_COL_INDEX, LOOP_COUNTER, &
I, J, L, IPW, NB, ICOL, ISEED(4) = (/26,67,52,197/), IPIV_B(N), IN, ITEMP, INFO

INDEX_ARRAY = 0
GIVENS_ARRAY = 0.0D+0
EXTRA_HOUSEHOLDER = 0.0D+0
EXTRA_TAU = 0.0D+0
ALLOCATE(TRAILING_COL_NORM(N-K),TAU_B(N))

! NUMBER OF ROWS IN B AND OMEGA
L = NB_MAX + P

! IPW
IPW = NB_MAX * NB_MAX + 1

! B IS THE COMPRESSION MATRIX, OMEGA IS A GAUSSIAN RANDOM MATRIX
ALLOCATE(B( L, N ), OMEGA( L, M ))

! GENERATE RANDOM MATRIX OMEGA, ENTRIES IN OMEGA SATISFY N(0,1)
CALL DLARNV(3, ISEED, L*M, OMEGA)

! COMPUTE B = OMEGA * A
CALL DGEMM('N', 'N', L, N, M, 1.0D+0, OMEGA, L, A, M, 0.0D+0, B, L)

! INITIALIZE IPIV
DO I = 1, N
	IPIV(I) = I
END DO

NB = NB_MAX
DO ICOL = 1, K, NB
	NB = MIN( K-ICOL+1, NB_MAX )

	! INITIALIZE IPIV_B
	IPIV_B = 0

	! DO PARTIAL QRCP ON B TO FIND NB PIVOTS
	CALL PARTIAL_DGEQPF( NB, L, N-ICOL+1, B(1, ICOL), L, IPIV_B(ICOL), TAU_B(ICOL), WORK, INFO )

	! DO SWAPS
	DO I = ICOL, N
		IPIV_B( I ) = -IPIV_B( I )
	END DO

	DO I = ICOL, N
		IF( IPIV_B( I ).GT.0 ) THEN
			GO TO 30
		ELSE
		END IF

		J = I
		IPIV_B( J ) = -IPIV_B( J )
		IN = IPIV_B( J ) + ICOL - 1

		40 CONTINUE
		IF( IPIV_B( IN ).GT.0 ) THEN
			GO TO 30
		ELSE
		END IF

		IF (J .NE. IN) THEN
			CALL DSWAP( M, A(1, J), 1, A(1, IN), 1 )

			ITEMP = IPIV(J)
			IPIV(J) = IPIV(IN)
			IPIV(IN) = ITEMP
		ELSE
		END IF

		IPIV_B( IN ) = -IPIV_B( IN )
		J = IN
		IN = IPIV_B( IN ) + ICOL - 1
		GO TO 40

		30 CONTINUE
	END DO

	! DO PANEL QR
	CALL DGEQR2( M-ICOL+1, NB, A(ICOL, ICOL), M, TAU(ICOL), WORK, INFO )

	! APPLY A BLOCK OF HOUSEHOLDER REFLECTIONS TO REST COLUMNS
	CALL DLARFT( 'FORWARD', 'COLUMNWISE', M-ICOL+1, NB, A(ICOL,ICOL), M, TAU(ICOL), WORK, NB_MAX )

	CALL DLARFB( 'LEFT', 'TRANSPOSE', 'FORWARD', 'COLUMNWISE', M-ICOL+1, N-ICOL+1-NB, &
		NB, A(ICOL,ICOL), M, WORK, NB_MAX, A(ICOL, ICOL+NB), M, WORK(IPW), N )

	! UPDATE B
	CALL DLASET( 'L', NB-1, NB-1, 0.0D+0, 0.0D+0, B(2, ICOL), L)
	CALL DTRSM('R', 'U', 'N', 'N', NB, NB, 1.0D+0, A(ICOL, ICOL), M, B(1, ICOL), L)
	CALL DGEMM( 'N', 'N', NB, N-ICOL-NB+1, NB, -1.0D+0, B(1, ICOL), L, A(ICOL, ICOL+NB), M, 1.0D+0, B(1, ICOL+NB), L)
END DO

ALLOCATE(OMEGA_TEMP(D,K+1))

! WE STORE THE HOUSEHOLDER REFLECTORS SOMEWHERE ELSE
CALL DLASET('ALL', M, K, 0.0D+0, 0.0D+0, HOUSEHOLDER, M)
CALL DLACPY('L', M-1, K, A(2,1), M, HOUSEHOLDER(2,1), M)
CALL DLASET('L', M-1, K, 0.0D+0, 0.0D+0, A(2,1), M)

LOOP_COUNTER = 1
DO WHILE (LOOP_COUNTER <= UPPER_BOUND)
	! WE NEED TO FIND ALPHA
	! COMPUTE THE COLUMN NORM OF ALL THE COLUMNS IN THE B 
	! TO ESTIMATE THE COLUMN NORM OF ALL THE COLUMNS IN THE TRAILING MATRIX OF A
	IF (LOOP_COUNTER .EQ. 1) THEN
		TRAILING_MAX_COL_NORM = 0.0D+0
		TRAILING_MAX_COL_INDEX = 1
		DO I = 1,N-K
			TRAILING_COL_NORM(I) = DLANGE('F', L, 1, B(1,K+I), L, WORK) ** 2 / DBLE(L)
			IF (TRAILING_COL_NORM(I) .GT. TRAILING_MAX_COL_NORM) THEN
				TRAILING_MAX_COL_NORM = TRAILING_COL_NORM(I)
				TRAILING_MAX_COL_INDEX = I
			ELSE
			END IF
		END DO

		! IF TRAILING_MAX_COL_INDEX != 1, THEN WE NEED DO SWAPS IN THE TRAILING MATRIX
		IF (TRAILING_MAX_COL_INDEX .NE. 1) THEN
			CALL DSWAP(M-K, A(K+1,K+TRAILING_MAX_COL_INDEX), 1, A(K+1,K+1), 1)
			DTEMP = TRAILING_COL_NORM(1)
			TRAILING_COL_NORM(1) = TRAILING_COL_NORM(TRAILING_MAX_COL_INDEX)
			TRAILING_COL_NORM(TRAILING_MAX_COL_INDEX) = DTEMP
			ITEMP = IPIV(K+1)
			IPIV(K+1) = IPIV(K+TRAILING_MAX_COL_INDEX)
			IPIV(K+TRAILING_MAX_COL_INDEX) = ITEMP
		ELSE
		END IF
		! WE NEED TO DO A PANEL QR
		CALL DGEQR2(M-K, 1, A(K+1,K+1), M, EXTRA_TAU(LOOP_COUNTER), WORK, INFO)

		! COPY THE GENERATED HOUSEHOLDER REFLECTOR TO EXTRA_HOUSEHOLDER
		CALL DLACPY('ALL', M-K, 1, A(K+1,K+1), M, EXTRA_HOUSEHOLDER(1,LOOP_COUNTER), M-K)

		! APPLY THE CORRESPONDING HOUSEHOLDER REFLECTOR TO THE TRAILING MATRIX
		CALL DORMQR('L', 'T', M-K, N-K-1, 1, A(K+1,K+1), M, EXTRA_TAU(LOOP_COUNTER), A(K+1,K+2), M, WORK, LWORK, INFO)

		! SET A(K+2:M,K+1) TO BE ZERO
		CALL DLASET('L', M-K-1, 1, 0.0D+0, 0.0D+0, A(K+2,K+1), M)

		! UPDATE TRAILING_COL_NORM, SUBTRACT THE ENTRY SQUARED ON K+1 ROW
		DO I = 2,N-K
			TRAILING_COL_NORM(I) = TRAILING_COL_NORM(I) - A(K+1,K+I) ** 2
		END DO
	ELSE 
		TRAILING_COL_NORM(1) = A(K+1,K+1) ** 2
		DO I = 2,N-K
			TRAILING_COL_NORM(I) = TRAILING_COL_NORM(I) +  A(K+1,K+I) ** 2
		END DO
		TRAILING_MAX_COL_NORM = 0.0D+0
		TRAILING_MAX_COL_INDEX = 1
		DO I = 1,N-K
			TRAILING_COL_NORM(I) = DLANGE('F', M-K, 1, A(K+1,K+I), M, WORK)
			IF (TRAILING_COL_NORM(I) .GT. TRAILING_MAX_COL_NORM) THEN
				TRAILING_MAX_COL_NORM = TRAILING_COL_NORM(I)
				TRAILING_MAX_COL_INDEX = I
			ELSE
			END IF
		END DO

		! IF TRAILING_MAX_COL_INDEX != 1, THEN WE NEED DO SWAPS IN THE TRAILING MATRIX
		IF (TRAILING_MAX_COL_INDEX .NE. 1) THEN
			CALL DSWAP(M-K, A(K+1,K+TRAILING_MAX_COL_INDEX), 1, A(K+1,K+1), 1)
			DTEMP = TRAILING_COL_NORM(1)
			TRAILING_COL_NORM(1) = TRAILING_COL_NORM(TRAILING_MAX_COL_INDEX)
			TRAILING_COL_NORM(TRAILING_MAX_COL_INDEX) = DTEMP
			ITEMP = IPIV(K+1)
			IPIV(K+1) = IPIV(K+TRAILING_MAX_COL_INDEX)
			IPIV(K+TRAILING_MAX_COL_INDEX) = ITEMP
		ELSE
		END IF
		! WE NEED TO DO A PANEL QR
		CALL DGEQR2(M-K, 1, A(K+1,K+1), M, EXTRA_TAU(LOOP_COUNTER), WORK, INFO)

		! COPY THE GENERATED HOUSEHOLDER REFLECTOR TO EXTRA_HOUSEHOLDER
		CALL DLACPY('ALL', M-K, 1, A(K+1,K+1), M, EXTRA_HOUSEHOLDER(1,LOOP_COUNTER), M-K)

		! APPLY THE CORRESPONDING HOUSEHOLDER REFLECTOR TO THE TRAILING MATRIX
		CALL DORMQR('L', 'T', M-K, N-K-1, 1, A(K+1,K+1), M, EXTRA_TAU(LOOP_COUNTER), A(K+1,K+2), M, WORK, LWORK, INFO)

		! SET A(K+2:M,K+1) TO BE ZERO
		CALL DLASET('L', M-K-1, 1, 0.0D+0, 0.0D+0, A(K+2,K+1), M)

		! UPDATE TRAILING_COL_NORM, SUBTRACT THE ENTRY SQUARED ON K+1 ROW
		DO I = 1,N-K
			TRAILING_COL_NORM(I) = TRAILING_COL_NORM(I) - A(K+1,K+I) ** 2
		END DO
	END IF

	! COMPUTE ALPHA
	ALPHA = ABS(A(K+1,K+1))
	! WRITE (*,*) 'ALPHA', ALPHA

	! GENERATE A RANDOM MATRIX OMEGA_TEMP TO COMPRESS \WIDEHAT{R}^{-T}
	CALL DLARNV(3, ISEED, D*(K+1), OMEGA_TEMP)

	! COMPUTE OMEGA_TEMP = OMEGA_TEMP * \WIDEHAT{R}^{-T}
	CALL DTRSM('R', 'U', 'T', 'N', D, K+1, 1.0D+0, A, M, OMEGA_TEMP, D)

	! FIND OMEGA_MAX_COL_NORM AND OMEGA_MAX_COL_INDEX
	OMEGA_MAX_COL_NORM = 0.0D+0
	OMEGA_MAX_COL_INDEX = 1 
	DO I = 1,K+1
		OMEGA_CURR_COL_NORM = DLANGE('F', D, 1, OMEGA_TEMP(1,I), D, WORK)
		IF (OMEGA_CURR_COL_NORM > OMEGA_MAX_COL_NORM) THEN
			OMEGA_MAX_COL_NORM = OMEGA_CURR_COL_NORM
			OMEGA_MAX_COL_INDEX = I
		ELSE
		END IF 
	END DO

	! CHECK THE CONDITION
	IF (ALPHA / SQRT(DBLE(D)) * OMEGA_MAX_COL_NORM .LE. G) THEN
		! WRITE (*,*) 'TOLERANCE', ALPHA / SQRT(DBLE(D)) * OMEGA_MAX_COL_NORM
		GO TO 100
	ELSE
		! WRITE (*,*) 'TOLERANCE', ALPHA / SQRT(DBLE(D)) * OMEGA_MAX_COL_NORM
		! DO ROUND ROBIN ON IPIV AND A
		IF (OMEGA_MAX_COL_INDEX .NE. K+1) THEN
			ITEMP = IPIV(OMEGA_MAX_COL_INDEX)
			DO I = OMEGA_MAX_COL_INDEX,K
				IPIV(I) = IPIV(I+1)
				CALL DSWAP(M, A(1, I), 1, A(1, I+1), 1)
			END DO 
			IPIV(K+1) = ITEMP

			! DO A SEQUENCE OF GIVENS ROTATIONS ON A TO REFORMULATE THE UPPER TRIANGULAR FORM
			! STORE DA, DB IN GIVENS_ARRAY
			! STORE OMEGA_MAX_COL_INDEX IN INDEX_ARRAY
			INDEX_ARRAY(LOOP_COUNTER) = OMEGA_MAX_COL_INDEX
			DO I = OMEGA_MAX_COL_INDEX, K
				DA = A(I,I)
				DB = A(I+1,I)
				CALL DROTG(DA, DB, C, S)
				CALL DROT(N-I+1, A(I,I), M, A(I+1,I), M, C, S)
				A(I+1,I) = 0.0D+0
				GIVENS_ARRAY(I,LOOP_COUNTER) = DA
				GIVENS_ARRAY(I,LOOP_COUNTER) = DB
			END DO
		ELSE
		END IF

		LOOP_COUNTER = LOOP_COUNTER + 1
	END IF
END DO
100 CONTINUE
NUM_SWAPS = LOOP_COUNTER - 1
DEALLOCATE(B, OMEGA, OMEGA_TEMP, TRAILING_COL_NORM, TAU_B)
END SUBROUTINE SRQR
