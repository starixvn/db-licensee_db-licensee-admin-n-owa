/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_NAPSel]
	@CustIds		VARCHAR(8000),
	@ReportMonth	DATETIME
AS
/*	Header:
	Created: 20190801@Bruce
	Task : Generate transfer amount to licensee code
	DB: DBACC.bodb02

	Revisions: 
		- 20190801@Bruce: Create Sp [#111586]
		- 20191007@Bruce: Filter data by custid [#120220]
		- 20210323@Percy: Support duo base currency [RedmineID: #152089]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @LastDayOfMonth DATE = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, @ReportMonth) + 1, 0))

	-- Transfer amount from current month is for last month
	-- Example: To get transfer amount of July we get data of August
	-- 
	DECLARE @FromDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @ReportMonth) + 1, 0)
	DECLARE @ToDate DATE =  DATEADD(DAY, -1, DATEADD(MONTH, 1, @FromDate))

	-- get licensee code list
	DECLARE @licensees TABLE (CustId INT, LicenseeCode VARCHAR(50))

	INSERT INTO @licensees(CustId,LicenseeCode)
	SELECT c.CustId, UPPER(c.username)
	FROM dbo.Customer c WITH(NOLOCK)
	WHERE c.CustId IN (SELECT val FROM dbo.strSplit(@CustIds,','))

	-- licensee super
	--
	DECLARE @licenseeTransferCode TABLE(CustId INT, LicenseeName VARCHAR(50))
	INSERT INTO @licenseeTransferCode(CustId,LicenseeName)
	SELECT tc.CustId, tc.LicenseeName
	FROM DBCUST.bodb_licensee.dbo.LicenseeTransferCode tc WITH(NOLOCK)
	WHERE @LastDayOfMonth BETWEEN tc.FromDate AND tc.ToDate

	DECLARE @licenseeSupers TABLE(CustId INT, LicenseeCode VARCHAR(50),SuperId INT, SuperCode VARCHAR(50))

	-- many licensee may have same code
	--
	INSERT INTO @licenseeSupers(CustId,LicenseeCode,SuperId, SuperCode)
	SELECT DISTINCT c.CustId, c.LicenseeCode, s.custid, s.username
	FROM @licensees c
	INNER JOIN @licenseeTransferCode tc ON c.CustId = tc.CustId
	INNER JOIN dbo.Dep_CustSuper s WITH(NOLOCK) ON s.[site] = tc.LicenseeName

	DECLARE @tmpBalanceUpDay AS TABLE (BalanceUpDay DATE, MoveBetsDay DATE)
	INSERT INTO @tmpBalanceUpDay(BalanceUpDay,MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	DECLARE @balanceUpDay DATE = (SELECT BalanceUpDay FROM @tmpBalanceUpDay)

	CREATE TABLE #TransferCust (CustId INT)
	INSERT INTO #TransferCust (CustId)
	SELECT DISTINCT CustId FROM @licenseeSupers
	UNION ALL SELECT DISTINCT SuperId FROM @licenseeSupers

	CREATE TABLE #transfer(
		Amount	MONEY,
		RefNo	BIGINT,
		CustId	INT
	)

	DECLARE @_FromDate SMALLDATETIME, @_ToDate SMALLDATETIME

	-- bettrans
	IF @ToDate >= @balanceUpDay
	BEGIN
		SELECT @_FromDate = CASE WHEN @FromDate > @balanceUpDay THEN @FromDate ELSE @balanceUpDay END
		SELECT @_ToDate = @ToDate

		INSERT INTO #transfer(Amount, RefNo, CustId)
		SELECT b.winlost - b.actual_stake, b.refno, b.custid
		FROM dbo.bettrans b WITH(NOLOCK)
			INNER JOIN #TransferCust c ON b.custid = c.CustId
		WHERE b.winlostdate BETWEEN @_FromDate AND @_ToDate AND b.bettype = 21003 AND b.oddsid=0
	END

	-- transfer
	IF @FromDate < @balanceUpDay
	BEGIN
		SELECT @_FromDate = @FromDate
		SELECT @_ToDate = CASE WHEN @ToDate < @balanceUpDay THEN @ToDate ELSE DATEADD(DAY, -1, @balanceUpDay) END

		INSERT INTO #transfer(Amount, RefNo, CustId)
		SELECT fi.winlost - fi.actual_stake, fi.refno, fi.custid
		FROM bodb_Archive.dbo.transfer_fi fi WITH(NOLOCK)
			INNER JOIN #TransferCust c ON fi.custid = c.CustId
		WHERE fi.winlostdate BETWEEN @FromDate AND @_ToDate AND fi.bettype = 21003 AND ISNULL(isReversal,0) = 0
	END

	CREATE NONCLUSTERED INDEX Idx_transfer ON #transfer (RefNo, CustId)

	SELECT SUM(a.Amount) Amount, UPPER(c.LicenseeCode) AS LicenseeCode, c.SuperCode AS Super
	FROM #transfer a
	INNER JOIN #transfer b ON a.refno = b.refno
	INNER JOIN @licenseeSupers c ON a.custid = c.CustId and b.custid = c.SuperId
	GROUP BY c.LicenseeCode, c.SuperCode
	HAVING SUM(a.Amount) <> 0

	DROP TABLE #transfer
	DROP TABLE #TransferCust
END
GO