/*<info serverAlias="DBACC-bodb02" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].LA_LicenseeReconciliation_CollectionSel
	@CustIds	VARCHAR(MAX),
	@FromDate	DATETIME,
	@ToDate		DATETIME
AS
/*	Header:
	Created: 20190820@Bruce
	Task : Get collection summary report
	DB: DBACC.bodb02

	Revisions: 
		- 20190820@Bruce: Create Sp [#111586]
		- 20190927@Bruce: Update OpeningBalance, ClosingBalance [#120220]
		- 20191017@Bruce: Filter by custid [#122229]
		- 20240227@Danny: Extend data type param input [RedmineID: #197267]
		- 20241120@Danny: replace strsplit function [RemineID: #212252]
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #collection(CustId INT, Amount Money, CollectedDate DATE)
	DECLARE @custidList TABLE(CustId INT)

	INSERT INTO @custidList(CustId)
	SELECT DISTINCT value FROM STRING_SPLIT(@CustIds,',')

	-- balance up day
	--
	DECLARE @tmpBalanceUpDay AS TABLE (BalanceUpDay DATE, MoveBetsDay DATE)
	INSERT INTO @tmpBalanceUpDay(BalanceUpDay,MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	DECLARE @balanceUpDay DATE, @moveBetsDay DATE
	SELECT @balanceUpDay = BalanceUpDay, @moveBetsDay = MoveBetsDay FROM @tmpBalanceUpDay

	IF @ToDate >= @balanceUpDay
	BEGIN
		DECLARE @_FromDate DATE = (CASE WHEN @FromDate >= @balanceUpDay THEN @FromDate ELSE @balanceUpDay END)

		INSERT INTO #collection(CustId,Amount,CollectedDate)
		SELECT tc.CustId, (tc.Credit - tc.Debit),tc.WinlostDate
		FROM dbo.Transfer_Coll tc WITH(NOLOCK)
		INNER JOIN @custidList s ON tc.CustId = s.CustId
		WHERE tc.WinlostDate BETWEEN @_FromDate AND @ToDate
	END

	IF @FromDate < @balanceUpDay
	BEGIN
		DECLARE @_ToDate DATE = (CASE WHEN @ToDate < @balanceUpDay THEN @ToDate ELSE DATEADD(day, -1, @balanceUpDay) END)

		INSERT INTO #collection(CustId,Amount,CollectedDate)
		SELECT tc.CustId, (tc.Credit - tc.Debit),tc.WinlostDate
		FROM bodb_archive.dbo.Transfer_Coll_bk tc WITH(NOLOCK)
		INNER JOIN @custidList s ON tc.CustId = s.CustId
		WHERE tc.WinlostDate BETWEEN @FromDate AND @_ToDate
	END

	SELECT CustId,CollectedDate, SUM(Amount) Amount	
	FROM #collection
	GROUP BY CustId,CollectedDate

	DROP TABLE #collection
END
GO