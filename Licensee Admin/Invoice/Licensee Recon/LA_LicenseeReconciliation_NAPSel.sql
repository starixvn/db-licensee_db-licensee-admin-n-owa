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
	DECLARE @Yesterday DATE = DATEADD(DAY, -1, GETDATE())

	IF (@ToDate > @Yesterday) SET @ToDate = @Yesterday

	-- get licensee code list
	DECLARE @licenseeCodeList TABLE (PartyId INT, LicenseeCode VARCHAR(50))
	INSERT INTO @licenseeCodeList(PartyId,LicenseeCode)
	SELECT PartyID, LicenseeCode FROM DBCUST.bodb_licensee.dbo.OAS_PartyDetail WITH(NOLOCK) WHERE ISNULL(LicenseeCode, '') <> ''

	-- licensee code to cust id
	-- some licensees may have same licensee code
	--
	DECLARE @customer AS TABLE (CustId int,Username VARCHAR(50))
	INSERT INTO @customer
	SELECT DISTINCT c.custid, c.Username
	FROM dbo.Customer c WITH(NOLOCK)
	INNER JOIN @licenseeCodeList l ON l.LicenseeCode=c.username
	WHERE l.PartyId IN (SELECT val FROM dbo.strSplit(@PartyIds,','))

	DECLARE @tmpBalanceUpDay AS TABLE (BalanceUpDay DATE, MoveBetsDay DATE)
	INSERT INTO @tmpBalanceUpDay(BalanceUpDay,MoveBetsDay)
	-- EXEC Age_SelBalanceUpDay
	-- TEST
	VALUES ('20190719','20190728')

	DECLARE @balanceUpDay DATE = (SELECT BalanceUpDay FROM @tmpBalanceUpDay)

	CREATE TABLE #transfer(
		Amount			MONEY,
		Super			VARCHAR(50),
		LicenseeCode	VARCHAR(50),
		RefNo			BIGINT
	)

	-- bettrans
	IF @ToDate >= @balanceUpDay
	BEGIN
		DECLARE @_FromDate DATE = (CASE WHEN @FromDate >= @balanceUpDay THEN @FromDate ELSE @balanceUpDay END)

		SELECT b.actual_stake,b.winlost, b.Username, b.refno,b.transid,b.custid
		INTO #bettrans
		FROM dbo.bettrans b WITH(NOLOCK)
		WHERE b.winlostdate BETWEEN @_FromDate AND @ToDate AND b.bettype = 21003 AND b.oddsid=0

		INSERT INTO #transfer (Amount, LicenseeCode,RefNo)
		SELECT SUM((b.actual_stake-b.winlost)), b.Username, b.refno
		FROM #bettrans b
		INNER JOIN @customer c ON  c.custid=b.custid
		GROUP BY b.Username, b.refno

		-- exclude reversal tickets
		DELETE #transfer WHERE Amount = 0

		;with x as (
			SELECT b.RefNo, MIN(a.transid) transid1, MAX(a.transid) transid2
			FROM #bettrans a INNER JOIN #transfer b ON a.refno=b.RefNo
			GROUP BY b.RefNo
		)
		UPDATE b SET Super = a.Username
		FROM #bettrans a
		INNER JOIN x ON a.refno=x.RefNo AND a.transid IN(x.transid1,x.transid2)
		INNER JOIN #transfer b ON b.RefNo=a.refno AND a.Username<>b.LicenseeCode

		DROP TABLE #bettrans
	END

	-- transfer
	IF @FromDate < @balanceUpDay
	BEGIN
		DECLARE @_ToDate DATE = (CASE WHEN @ToDate < @balanceUpDay THEN @ToDate ELSE DATEADD(day, -1, @balanceUpDay) END)

		SELECT transid, custid, actual_stake, winlost, refno,isReversal
		INTO #transfer_fi
		FROM bodb_Archive.dbo.transfer_fi fi WITH(NOLOCK)
		WHERE fi.winlostdate BETWEEN @FromDate AND @_ToDate AND fi.bettype = 21003 AND ISNULL(isReversal,0) = 0

		INSERT INTO #transfer (Amount, LicenseeCode,RefNo)
		SELECT (b.actual_stake-b.winlost) Amount, c.Username, b.refno
		FROM #transfer_fi b
		INNER JOIN @customer c ON  c.custid=b.custid

		;with x as (
			SELECT b.RefNo, MIN(a.transid) transid1, MAX(a.transid) transid2
			FROM #transfer_fi a INNER JOIN #transfer b ON a.refno=b.RefNo
			WHERE b.Super IS NULL
			GROUP BY b.RefNo
		)
		UPDATE b SET Super = c.Username
		FROM #transfer_fi a
		INNER JOIN x ON a.refno=x.RefNo AND a.transid IN(x.transid1,x.transid2)
		INNER JOIN dbo.customer c WITH(NOLOCK) ON c.custid=a.custid
		INNER JOIN #transfer b ON b.RefNo=a.refno AND c.Username<>b.LicenseeCode

		DROP TABLE #transfer_fi
	END

	SELECT t.Super, t.LicenseeCode, SUM(t.Amount) Amount
	FROM #transfer t
	INNER JOIN @customer c ON t.LicenseeCode = c.Username
	GROUP BY t.LicenseeCode,t.Super

	DROP TABLE #transfer
END
GO