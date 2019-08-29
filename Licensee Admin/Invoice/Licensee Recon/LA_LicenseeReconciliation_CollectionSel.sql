/*<info serverAlias="DBACC-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

CREATE PROCEDURE [dbo].LA_LicenseeReconciliation_CollectionSel
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

	-- get licensee code list
	--
	DECLARE @licenseeCodeList TABLE (PartyId INT, PartyName VARCHAR(50), LicenseeCode VARCHAR(50))
	INSERT INTO @licenseeCodeList(PartyId, PartyName,LicenseeCode)
	SELECT p.PartyID, p.PartyName, d.LicenseeCode
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail d WITH(NOLOCK) ON d.PartyID=p.PartyID
	WHERE p.PartyType = 1
		AND ISNULL(d.LicenseeCode, '') <> ''
		AND p.PartyId IN (SELECT val FROM dbo.strSplit(@PartyIds,','))

	CREATE TABLE #statement(
		CustId				INT,
		--LicenseeCode		VARCHAR(50),
		LicenseeName		VARCHAR(100),
		OpeningBalance		MONEY,
		OpeningBalanceDate	DATE
	)

	CREATE NONCLUSTERED INDEX Idx_tmp_statement ON #statement (CustId)

	-- licensee code to cust id
	-- some licensees may have same licensee code
	-- Ex: Licensee A, Licensee B => Licensee A & Licensee B
	--
	INSERT INTO #statement(CustId,LicenseeName, OpeningBalance, OpeningBalanceDate)
	SELECT c.custid, STUFF((
			SELECT ' & ' + lc.PartyName
			FROM @licenseeCodeList lc 
			WHERE c.username = lc.LicenseeCode
			FOR XML PATH(''),TYPE).value('(./text())[1]','VARCHAR(200)')
		,1,3,''), 0, '19000101'
	FROM dbo.Customer c WITH(NOLOCK)
	INNER JOIN @licenseeCodeList l ON l.LicenseeCode=c.username
	GROUP BY c.custid, c.Username

	DECLARE @tmpBalanceUpDay AS TABLE (BalanceUpDay DATE, MoveBetsDay DATE)
	INSERT INTO @tmpBalanceUpDay(BalanceUpDay,MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	DECLARE @balanceUpDay DATE = (SELECT BalanceUpDay FROM @tmpBalanceUpDay)
	DECLARE @previousDate DATE = DATEADD(DAY,-1, @FromDate)

	IF @previousDate >= @balanceUpDay
	BEGIN
		UPDATE s SET
			OpeningBalance = a.OpeningBalance,
			OpeningBalanceDate = a.WinlostDate
		FROM #statement s
		INNER JOIN bodb_Report.dbo.rptTotalBalance_Active a WITH(NOLOCK) ON s.CustId = a.CustID
		WHERE a.WinlostDate = @previousDate
	END
	ELSE
	BEGIN
		;WITH cte_OpeningBalanceDate AS (
			SELECT MAX(rs.accdate) accdate, rs.custid
			FROM #statement s INNER JOIN bodb_Report.dbo.Statement rs WITH (NOLOCK) ON s.CustId = rs.custid
			WHERE rs.transtype = 'Bal'
				AND rs.transdesc = 'OPENING BALANCE'
				AND rs.accdate <= @previousDate
			GROUP BY rs.custid
		)
		UPDATE s SET OpeningBalanceDate = ob.accdate, OpeningBalance = r.totalamt
		FROM #statement s INNER JOIN cte_OpeningBalanceDate ob ON s.CustId = ob.custid
		INNER JOIN bodb_Report.dbo.Statement r WITH (NOLOCK) ON r.custid=s.CustId and r.accdate=ob.accdate
	END

	;WITH cte_OpeningBalance AS(
		SELECT tf.custid, SUM(tf.winlost - tf.actual_stake) amount
		FROM bodb_archive.dbo.transfer_fi tf WITH(NOLOCK)
		INNER JOIN #statement s ON s.CustId=tf.custid
		WHERE tf.winlostdate BETWEEN s.OpeningBalanceDate AND @previousDate
		GROUP BY tf.custid
	)
	UPDATE st SET OpeningBalance = (OpeningBalance + ob.amount)
	FROM #statement st INNER JOIN cte_OpeningBalance ob ON st.CustId = ob.custid

	CREATE TABLE #collection(CustId INT, Amount Money, CollectedDate DATE)

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
END
GO