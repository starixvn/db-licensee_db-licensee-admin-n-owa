/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_BalanceSel]
	@CustIds		VARCHAR(8000),
	@ReportDate		DATETIME,
	@Environment	VARCHAR(50) = 'DEV'
AS
/*	Header:
	Created: 20200122@Parsons
	Task : Retrieve Balance B/f from NAP for Collection sheet
	DB: DBACC.bodb02

	Revisions: 
		- 20200122@Parsons: - Create Sp [#125221]
							- Fix Setup Fee issue [#125221]
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

	-- ***Setup fee issue***
	--
	-- Remove cust which has not been issued Software Data Fee
	DECLARE @OW_PartyList TABLE(PartyId INT,PartyName VARCHAR(50),BrandName VARCHAR(50),ParentId INT)

	INSERT INTO @OW_PartyList(PartyId,PartyName,BrandName,ParentId)
	EXEC DBLIC.bodb_licensee.dbo.LA_PartyListSel

	DELETE @OW_PartyList WHERE ParentId <> 1-- OW

	;WITH cte_ValidCustTable AS
	(   SELECT DISTINCT s.CustId
		FROM #statement s
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.LicenseeCode = s.LicenseeCode
			INNER JOIN bodb_licensee.dbo.LA_InvoiceHeader h WITH(NOLOCK) ON d.PartyId = h.PartyId
		WHERE h.StatusId = 0-- normal invoice
			AND h.InvoiceHeaderId NOT IN (6208, 6207) -- temporary exclude these credit notes
			AND h.Environment = @Environment
			AND InvoiceType = 1
			AND (h.FromDate < @ReportDate)
    )
	DELETE s
	FROM #statement s
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.LicenseeCode = s.LicenseeCode
	WHERE d.PartyID NOT IN (SELECT ow.PartyId FROM @OW_PartyList ow)
		  AND	CustId NOT IN (SELECT cte.CustId FROM cte_ValidCustTable cte)

	-- balance up day
	--
	DECLARE @tmpBalanceUpDay AS TABLE (BalanceUpDay DATE, MoveBetsDay DATE)
	INSERT INTO @tmpBalanceUpDay(BalanceUpDay,MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	DECLARE @balanceUpDay DATE, @moveBetsDay DATE
	SELECT @balanceUpDay = BalanceUpDay, @moveBetsDay = MoveBetsDay FROM @tmpBalanceUpDay

	DECLARE @OpeningBalanceDate DATE = DATEADD(DAY,-1,@ReportDate)
	DECLARE @step TINYINT = 0

	-- rptTotalBalance_Active
	-- step 1
	IF @ReportDate > @moveBetsDay
	BEGIN
		SET @step = 1

		INSERT INTO #tmpOB(CustId,OpeningBalanceDate)
		SELECT a.CustID, MAX(a.WinlostDate)
		FROM #statement s
		INNER JOIN bodb_Report.dbo.rptTotalBalance_Active a WITH(NOLOCK) ON s.CustId = a.CustID
		WHERE a.WinlostDate <= @ReportDate
		GROUP BY a.CustID

		UPDATE s SET OpeningBalance = a.OpeningBalance
		FROM #statement s
		INNER JOIN #tmpOB t ON t.CustId=s.CustId
		INNER JOIN bodb_Report.dbo.rptTotalBalance_Active a WITH(NOLOCK) ON t.CustId = a.CustID AND t.OpeningBalanceDate=a.WinlostDate
	END

	-- rptstatement
	-- step 2
	IF (@ReportDate > @balanceUpDay AND @ReportDate <= @moveBetsDay) OR (EXISTS (SELECT TOP 1 1 FROM #statement WHERE OpeningBalance IS NULL) AND @step = 1)
	BEGIN
		DELETE #tmpOB
		SET @step = 2

		INSERT INTO #tmpOB(CustId,OpeningBalanceDate)
		SELECT a.CustID, MAX(a.WinlostDate)
		FROM #statement s
		INNER JOIN bodb_report.dbo.rptstatement a WITH(NOLOCK) ON s.CustId = a.CustID
		WHERE a.WinlostDate < @ReportDate AND s.OpeningBalance IS NULL
		GROUP BY a.CustID
		
		UPDATE s SET OpeningBalance = a.closingbalance
		FROM #statement s
		INNER JOIN #tmpOB t ON t.CustId=s.CustId
		INNER JOIN bodb_Report.dbo.rptstatement a WITH(NOLOCK) ON t.CustId = a.CustID AND t.OpeningBalanceDate=a.WinlostDate
	END

	-- rptstatement_Old
	-- step 3
	IF @ReportDate <= @balanceUpDay OR (EXISTS (SELECT TOP 1 1 FROM #statement WHERE OpeningBalance IS NULL) AND @step = 2)
	BEGIN
		DELETE #tmpOB
		SET @step = 3

		INSERT INTO #tmpOB(CustId,OpeningBalanceDate)
		SELECT a.CustID, MAX(a.WinlostDate)
		FROM #statement s
		INNER JOIN bodb_report.dbo.rptstatement_Old a WITH(NOLOCK) ON s.CustId = a.CustID
		WHERE a.WinlostDate < @ReportDate AND s.OpeningBalance IS NULL
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