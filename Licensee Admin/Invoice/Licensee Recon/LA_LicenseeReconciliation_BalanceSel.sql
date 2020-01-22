/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_BalanceSel]
	@CustIds		VARCHAR(8000),
	@FromDate	DATETIME
AS
/*	Header:
	Created: 20200122@Parsons
	Task : Retrieve Balance B/f from NAP for Collection sheet
	DB: DBACC.bodb02

	Revisions: 
		- 20200122@Parsons: Create Sp [#125221]
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #statement(
		CustId				INT,
		LicenseeCode		VARCHAR(50),
		OpeningBalance		MONEY
	)

	CREATE TABLE #tmpOB(
		CustId				INT,
		OpeningBalanceDate	DATE
	)

	CREATE NONCLUSTERED INDEX Idx_tmp_statement ON #statement (CustId)
	CREATE NONCLUSTERED INDEX Idx_tmp_OB ON #tmpOB (CustId)

	-- map licensee
	--
	DECLARE @tmpCust TABLE(CustId INT,LicenseeCode VARCHAR(50))

	INSERT INTO @tmpCust(CustId,LicenseeCode)
	SELECT c.CustId, c.username
	FROM dbo.Customer c WITH(NOLOCK)
	INNER JOIN dbo.strSplit(@CustIds,',') c2 ON c.CustId = c2.val

	-- many licensees may have same code, ex: honbet, new honbet
	--
	-- remove duplicated code
	--
	INSERT INTO #statement(CustId,LicenseeCode)
	SELECT DISTINCT CustId, LicenseeCode FROM @tmpCust

	-- balance up day
	--
	DECLARE @tmpBalanceUpDay AS TABLE (BalanceUpDay DATE, MoveBetsDay DATE)
	INSERT INTO @tmpBalanceUpDay(BalanceUpDay,MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	DECLARE @balanceUpDay DATE, @moveBetsDay DATE
	SELECT @balanceUpDay = BalanceUpDay, @moveBetsDay = MoveBetsDay FROM @tmpBalanceUpDay

	DECLARE @OpeningBalanceDate DATE = DATEADD(DAY,-1,@FromDate)
	DECLARE @step TINYINT = 0

	-- rptTotalBalance_Active
	-- step 1
	IF @FromDate > @moveBetsDay
	BEGIN
		SET @step = 1

		INSERT INTO #tmpOB(CustId,OpeningBalanceDate)
		SELECT a.CustID, MAX(a.WinlostDate)
		FROM #statement s
		INNER JOIN bodb_Report.dbo.rptTotalBalance_Active a WITH(NOLOCK) ON s.CustId = a.CustID
		WHERE a.WinlostDate <= @FromDate
		GROUP BY a.CustID

		UPDATE s SET OpeningBalance = a.OpeningBalance
		FROM #statement s
		INNER JOIN #tmpOB t ON t.CustId=s.CustId
		INNER JOIN bodb_Report.dbo.rptTotalBalance_Active a WITH(NOLOCK) ON t.CustId = a.CustID AND t.OpeningBalanceDate=a.WinlostDate
	END

	-- rptstatement
	-- step 2
	IF (@FromDate > @balanceUpDay AND @FromDate <= @moveBetsDay) OR (EXISTS (SELECT TOP 1 1 FROM #statement WHERE OpeningBalance IS NULL) AND @step = 1)
	BEGIN
		DELETE #tmpOB
		SET @step = 2

		INSERT INTO #tmpOB(CustId,OpeningBalanceDate)
		SELECT a.CustID, MAX(a.WinlostDate)
		FROM #statement s
		INNER JOIN bodb_report.dbo.rptstatement a WITH(NOLOCK) ON s.CustId = a.CustID
		WHERE a.WinlostDate < @FromDate AND s.OpeningBalance IS NULL
		GROUP BY a.CustID
		
		UPDATE s SET OpeningBalance = a.closingbalance
		FROM #statement s
		INNER JOIN #tmpOB t ON t.CustId=s.CustId
		INNER JOIN bodb_Report.dbo.rptstatement a WITH(NOLOCK) ON t.CustId = a.CustID AND t.OpeningBalanceDate=a.WinlostDate
	END

	-- rptstatement_Old
	-- step 3
	IF @FromDate <= @balanceUpDay OR (EXISTS (SELECT TOP 1 1 FROM #statement WHERE OpeningBalance IS NULL) AND @step = 2)
	BEGIN
		DELETE #tmpOB
		SET @step = 3

		INSERT INTO #tmpOB(CustId,OpeningBalanceDate)
		SELECT a.CustID, MAX(a.WinlostDate)
		FROM #statement s
		INNER JOIN bodb_report.dbo.rptstatement_Old a WITH(NOLOCK) ON s.CustId = a.CustID
		WHERE a.WinlostDate < @FromDate AND s.OpeningBalance IS NULL
		GROUP BY a.CustID
		
		UPDATE s SET OpeningBalance = a.closingbalance
		FROM #statement s
		INNER JOIN #tmpOB t ON t.CustId=s.CustId
		INNER JOIN bodb_Report.dbo.rptstatement_Old a WITH(NOLOCK) ON t.CustId = a.CustID AND t.OpeningBalanceDate=a.WinlostDate
	END

	SELECT * FROM #statement

	DROP TABLE #tmpOB
	DROP TABLE #statement
END
GO