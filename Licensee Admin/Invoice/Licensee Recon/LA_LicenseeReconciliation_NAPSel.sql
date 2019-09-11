/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_NAPSel]
	@PartyIds		VARCHAR(4000),
	@ReportMonth	DATETIME
AS
/*	Header:
	Created: 20190801@Bruce
	Task : Generate transfer amount to licensee code
	DB: DBACC.bodb02

	Revisions: 
		- 20190801@Bruce: Create Sp [#111586]
*/
BEGIN
	SET NOCOUNT ON

	-- Transfer amount from current month is for last month
	-- Example: To get transfer amount of July we get data of August
	-- 
	DECLARE @FromDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @ReportMonth) + 1, 0)
	DECLARE @ToDate DATE =  DATEADD(DAY, -1, DATEADD(MONTH, 1, @FromDate))

	DECLARE @partyIdList TABLE(Id INT)
	INSERT INTO @partyIdList SELECT val FROM dbo.strSplit(@PartyIds,',')

	-- get licensee code list
	 DECLARE @licensees TABLE (CustId INT, LicenseeCode VARCHAR(50))   

	-- map licensee
	--
	INSERT INTO @licensees(CustId,LicenseeCode)
	SELECT c.CustId, c.username
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
	INNER JOIN @partyIdList pl ON pl.Id = p.PartyID
	INNER JOIN dbo.Customer c WITH(NOLOCK) on c.username=d.LicenseeCode
	WHERE p.PartyType IN (1,5) AND pl.Id > 0

	-- map unidentified licensees
	-- indicated by -custid
	INSERT INTO @licensees(CustId,LicenseeCode)
	SELECT c.custid, c.username
	FROM dbo.Customer c WITH(NOLOCK)
	INNER JOIN @partyIdList pl ON c.custid = -pl.Id
	WHERE pl.Id < 0

	-- licensee super
	--
	DECLARE @licenseeSupers TABLE(CustId INT, LicenseeCode VARCHAR(50),SuperId INT, SuperCode VARCHAR(50))
	INSERT INTO @licenseeSupers(CustId,LicenseeCode,SuperId, SuperCode)
	SELECT c.CustId, c.LicenseeCode, s.custid, s.username
	FROM @licensees c
	INNER JOIN DBCUST.bodb_licensee.dbo.LicenseeTransferCode tc WITH(NOLOCK) ON c.CustId = tc.CustId
	INNER JOIN dbo.Dep_CustSuper s WITH(NOLOCK) ON s.[site] = tc.LicenseeName

	DECLARE @tmpBalanceUpDay AS TABLE (BalanceUpDay DATE, MoveBetsDay DATE)
	INSERT INTO @tmpBalanceUpDay(BalanceUpDay,MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	DECLARE @balanceUpDay DATE = (SELECT BalanceUpDay FROM @tmpBalanceUpDay)

	CREATE TABLE #transfer(
		Amount	MONEY,
		RefNo	BIGINT,
		CustId	INT
	)

	CREATE NONCLUSTERED INDEX Idx_transfer ON #transfer (RefNo, CustId)

	-- bettrans
	IF @ToDate >= @balanceUpDay
	BEGIN
		DECLARE @_FromDate DATE = (CASE WHEN @FromDate >= @balanceUpDay THEN @FromDate ELSE @balanceUpDay END)

		INSERT INTO #transfer(Amount, RefNo, CustId)
		SELECT winlost - actual_stake, refno, custid
		FROM dbo.bettrans b WITH(NOLOCK)
		WHERE b.winlostdate BETWEEN @_FromDate AND @ToDate AND b.bettype = 21003 AND b.oddsid=0
	END

	-- transfer
	IF @FromDate < @balanceUpDay
	BEGIN
		DECLARE @_ToDate DATE = (CASE WHEN @ToDate < @balanceUpDay THEN @ToDate ELSE DATEADD(day, -1, @balanceUpDay) END)

		INSERT INTO #transfer(Amount, RefNo, CustId)
		SELECT winlost - actual_stake, refno, custid
		FROM bodb_Archive.dbo.transfer_fi fi WITH(NOLOCK)
		WHERE fi.winlostdate BETWEEN @FromDate AND @_ToDate AND fi.bettype = 21003 AND ISNULL(isReversal,0) = 0
	END

	SELECT SUM(a.Amount) Amount, c.LicenseeCode, c.SuperCode AS Super
	FROM #transfer a
	INNER JOIN #transfer b ON a.refno = b.refno
	INNER JOIN @licenseeSupers c ON a.custid = c.CustId and b.custid = c.SuperId
	GROUP BY c.LicenseeCode, c.SuperCode
	HAVING SUM(a.Amount) <> 0

	DROP TABLE #transfer
END
GO