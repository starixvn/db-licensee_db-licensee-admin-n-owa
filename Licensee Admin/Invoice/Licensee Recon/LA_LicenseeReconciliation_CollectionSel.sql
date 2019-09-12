/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].LA_LicenseeReconciliation_CollectionSel
	@PartyIds	VARCHAR(4000),
	@FromDate	DATETIME,
	@ToDate		DATETIME
AS
/*	Header:
	Created: 20190820@Bruce
	Task : Get collection summary report
	DB: DBACC.bodb02

	Revisions: 
		- 20190820@Bruce: Create Sp [#111586]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @partyIdList TABLE(Id INT)
	INSERT INTO @partyIdList SELECT val FROM dbo.strSplit(@PartyIds,',')

	CREATE TABLE #collection(CustId INT, Amount Money, CollectedDate DATE)
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
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
	INNER JOIN @partyIdList pl ON pl.Id = p.PartyID
	INNER JOIN dbo.Customer c WITH(NOLOCK) on c.username=d.LicenseeCode
	WHERE p.PartyType IN (1,5) AND pl.Id > 0

	-- map unidentified licensees
	-- indicated by -custid
	INSERT INTO @tmpCust(CustId,LicenseeCode)
	SELECT c.custid, c.username
	FROM dbo.Customer c WITH(NOLOCK)
	INNER JOIN @partyIdList pl ON c.custid = -pl.Id
	WHERE pl.Id < 0

	-- many licensees may have same code
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
		WHERE a.WinlostDate < @FromDate
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
		
		UPDATE s SET OpeningBalance = a.OpeningBalance
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
		
		UPDATE s SET OpeningBalance = a.OpeningBalance
		FROM #statement s
		INNER JOIN #tmpOB t ON t.CustId=s.CustId
		INNER JOIN bodb_Report.dbo.rptstatement a WITH(NOLOCK) ON t.CustId = a.CustID AND t.OpeningBalanceDate=a.WinlostDate
	END

	UPDATE #statement SET OpeningBalance = 0 WHERE OpeningBalance iS NULL

	IF @ToDate >= @balanceUpDay
	BEGIN
		DECLARE @_FromDate DATE = (CASE WHEN @FromDate >= @balanceUpDay THEN @FromDate ELSE @balanceUpDay END)

		INSERT INTO #collection(CustId,Amount,CollectedDate)
		SELECT tc.CustId, (tc.Credit - tc.Debit),tc.WinlostDate
		FROM dbo.Transfer_Coll tc WITH(NOLOCK)
		INNER JOIN #statement s ON tc.CustId = s.CustId
		WHERE tc.WinlostDate BETWEEN @_FromDate AND @ToDate
	END

	IF @FromDate < @balanceUpDay
	BEGIN
		DECLARE @_ToDate DATE = (CASE WHEN @ToDate < @balanceUpDay THEN @ToDate ELSE DATEADD(day, -1, @balanceUpDay) END)

		INSERT INTO #collection(CustId,Amount,CollectedDate)
		SELECT tc.CustId, (tc.Credit - tc.Debit),tc.WinlostDate
		FROM bodb_archive.dbo.Transfer_Coll_bk tc WITH(NOLOCK)
		INNER JOIN #statement s ON tc.CustId = s.CustId
		WHERE tc.WinlostDate BETWEEN @FromDate AND @_ToDate
	END

	select * from #statement
	select * from #collection

	DROP TABLE #statement
	DROP TABLE #collection
	DROP TABLE #tmpOB
END
GO