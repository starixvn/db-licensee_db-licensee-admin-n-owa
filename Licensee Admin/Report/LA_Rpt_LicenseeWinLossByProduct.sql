USE [bodb_Licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinLossByProduct]
	@PartyIdString		VARCHAR(500),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(10)
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee

	Revisions:
		+ 2015.08.06: Invoice Amount - Generate
		+ 2015.09.15: Get Amount by PartyId List.
		+ 2015.10.20@Bravo: Add Zelianta
		+ 2015.12.15@Bruce: Add MGCLC and MGCRNG
		+ 2016.05.05@Bravo: Add VB Data
		+ 2016.10.12@Bruce: Order result by group
*/
/*	Example:
	USE bodb_Licensee
	DECLARe @PartyIdString	VARCHAR(500)	= '14,15,29,25,30'
	DECLARE @FromDate		DATETIME		= '2015-8-1'
	DECLARE @ToDate			DATETIME		= '2015-8-31'
	DECLARe @BaseCurrencyName	VARCHAR(10)		= 'GBP'
			
	EXEC [LA_Rpt_LicenseeWinLossByProduct] @PartyIdString, @FromDate, @ToDate, @BaseCurrencyName
	
*/
BEGIN
	SET NOCOUNT ON
	
	-- Region: Get party charge rate info
	DECLARE @ProductCode VARCHAR(100)= 'SB,NG,RB,VS,LC,CS,KN,AGC,GD,VG,MGCLC,MGCRNG,VB'
	
	-- Region: Get Party ID
	DECLARE @PartyIdTable TABLE (Id INT NOT NULL)
	DECLARE @Delimiter CHAR(1)=','

	;WITH SeparatedTable (STARTVAL, STOPVAL)
	AS 
	(
		SELECT
			STARTVAL = CAST(1 AS INT),
			STOPVAL = CHARINDEX(@Delimiter, @PartyIdString + @Delimiter)
		UNION ALL SELECT
			STARTVAL = STOPVAL + 1,
			STOPVAL = CHARINDEX(@Delimiter, @PartyIdString + @Delimiter, STOPVAL + 1)
		FROM SeparatedTable
		WHERE STOPVAL > 0
	)
	INSERT @PartyIdTable (Id)
	SELECT LTRIM(RTRIM(SUBSTRING(@PartyIdString, STARTVAL,	CASE
																WHEN STOPVAL > 0 THEN STOPVAL - STARTVAL
																ELSE 0
															END)))
	FROM SeparatedTable
	WHERE STOPVAL > 0
	OPTION (MAXRECURSION 0)
	-- End Region
	
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			BettypeRef	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, BettypeRef)
	(
		SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate, Bettype -- this field should be BettypeRef not Bettype
		FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)
	-- End region
	
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End region
	
	-- Region: Get Winloss data
	CREATE	TABLE #TempData (
			LicenseeId	INT,
			PartyId		INT,
			rptDate		DATETIME,
			CurrencyId	INT,
			MemberWL	MONEY,
			AWinLoss	MONEY,
			AComm		MONEY,
			ProductId	TINYINT,
			BettypeRef	INT)
	
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,MemberWL,AWinLoss,AComm,ProductId,BettypeRef)
	(
		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(ISNULL(b.MemberWL, 0)) Winloss,
				SUM(ISNULL(b.GrossWL, 0)) AS AWinLoss,
				SUM(ISNULL(b.CommissionA, 0)) AS AComm,
				b.ProductId,
				ISNULL(sbr.BettypeRef, -1)
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON b.SiteID = p.OldRefID AND p.PartyType = 1
				LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.Bettype = b.Bettype
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903)
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, b.ProductId, ISNULL(sbr.BettypeRef, -1)
	)
	
	-- EndRegion

	-- Region: Generate licensee name & group
	DECLARE @TempPartyList AS TABLE(
		PartyId		INT,
		PartyName	VARCHAR(200),
		BranchName	VARCHAR(200),
		ParentId	INT
	)
	INSERT INTO @TempPartyList
	EXECUTE dbo.LA_PartyListSel
	
	CREATE TABLE #LicenseeAmount(
		GroupName	VARCHAR(200),
		GroupId		INT,
		LicenseeId	INT,
		PartyId		INT,
		PartyName	VARCHAR(200),
		SB			MONEY, --SB
		RB			MONEY, -- RB
		NG			MONEY, -- NG	
		BA			MONEY, -- BA
		LC			MONEY, -- LC
		VS			MONEY, -- VS
		CS			MONEY, -- CS
		KN			MONEY, -- KN
		AGC			MONEY, -- AGC
		GD			MONEY, -- GD
		VG			MONEY, -- VG
		MGCLC		MONEY, -- Microgaming - Live Casino
		MGCRNG		MONEY,  -- Microgaming - RNG Casino
		VB			MONEY  -- VB
	)
	INSERT INTO #LicenseeAmount(GroupName, GroupId, LicenseeId, PartyId,PartyName)
	SELECT	CASE
				WHEN p.PartyId = 1 THEN 'ONEWorks'
				WHEN p.PartyId = 11 THEN 'Boping'
				WHEN p.PartyId = 98 THEN 'Zelianta'
				ELSE 'Credit'
			END	AS PartyName,
			p.PartyId,
			op.OldRefID,
			t.PartyId, 
			t.PartyName
	FROM	@TempPartyList t INNER JOIN @TempPartyList p ON t.ParentId = p.PartyId
			INNER JOIN dbo.OAS_Party op WITH (NOLOCK) ON op.PartyID = t.PartyId
	WHERE	t.ParentId != 0
			AND t.PartyId IN (SELECT Id FROM @PartyIdTable)

	-- BA
	;WITH AmountDueBA AS
	(
		SELECT	d.LicenseeId,
				SUM(-(MemberWL + AComm) * e.Rate) Amount
		FROM	#TempData d
				INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
		WHERE	d.ProductId = 3
		GROUP	BY d.LicenseeId
	)
	UPDATE	d
	SET		BA = a.Amount
	FROM	#LicenseeAmount d INNER JOIN AmountDueBA a ON a.LicenseeId = d.LicenseeId
	
	-- RB
	;WITH AmountDueRacing AS
	(
		SELECT	d.LicenseeId,
				SUM(-(MemberWL + AWinloss + AComm) * e.Rate) Amount
		FROM	#TempData d
				INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
		WHERE	d.ProductId = 1 --RB
		GROUP	BY d.LicenseeId
	)
	UPDATE	d
	SET		RB = a.Amount
	FROM	#LicenseeAmount d INNER JOIN AmountDueRacing a ON a.LicenseeId = d.LicenseeId

	;WITH AmountDueByProduct AS
	(
		SELECT	d.PartyId,
				d.LicenseeId,
				ISNULL(SUM(CASE WHEN d.ProductId = 0  THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS SB,
				ISNULL(SUM(CASE WHEN d.ProductId = 2  THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS NG,
				ISNULL(SUM(CASE WHEN d.ProductId = 4  THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS LC,
				ISNULL(SUM(CASE WHEN d.ProductId = 5  THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS VS,
				ISNULL(SUM(CASE WHEN d.ProductId = 6  THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS CS,
				ISNULL(SUM(CASE WHEN d.ProductId = 8  THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS KN,
				ISNULL(SUM(CASE WHEN d.ProductId = 10 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS AGC,
				ISNULL(SUM(CASE WHEN d.ProductId = 11 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS GD,
				ISNULL(SUM(CASE WHEN d.ProductId = 12 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS VG,
				ISNULL(SUM(CASE WHEN d.ProductId = 14 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS MGCLC,
				ISNULL(SUM(CASE WHEN d.ProductId = 17 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS MGCRNG,
				ISNULL(SUM(CASE WHEN d.ProductId = 22 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS VB
		FROM	#TempData d
				INNER JOIN @PartyChargeInfo ci ON	d.PartyId = ci.PartyId 
													AND ci.ProductId = d.ProductId 
													AND d.rptDate BETWEEN ci.FromDate AND ci.ToDate
													AND d.BettypeRef = ci.BettypeRef
				INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
		GROUP BY d.PartyId,
				 d.LicenseeId
	)
	UPDATE	l
	SET		SB = a.SB,
			NG = a.NG,
			LC = a.LC,
			VS = a.VS,
			CS = a.CS,
			KN = a.KN,
			AGC = a.AGC,
			GD = a.GD,
			VG = a.VG,
			MGCLC = a.MGCLC,
			MGCRNG = a.MGCRNG,
			VB = a.VB
	FROM	#LicenseeAmount l
			INNER JOIN AmountDueByProduct a ON a.LicenseeId = l.LicenseeId AND a.PartyId = l.PartyId
	
	DELETE	FROM #LicenseeAmount
	WHERE	SB IS NULL
			AND RB IS NULL
			AND NG IS NULL
			AND BA IS NULL
			AND LC IS NULL
			AND VS IS NULL
			AND CS IS NULL
			AND KN IS NULL
			AND AGC IS NULL
			AND GD IS NULL
			AND VG IS NULL
			AND MGCLC IS NULL
			AND MGCRNG IS NULL
			AND VB IS NULL
	
	SELECT	l.GroupName,l.PartyName,l.SB,l.RB,l.NG,l.BA,l.LC,l.VS,l.CS, l.KN,l.AGC,l.GD,l.VG,l.MGCLC,l.MGCRNG,l.VB
	FROM	#LicenseeAmount l
	ORDER BY l.GroupId, l.PartyId
	
	-- EndRegion

	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #LicenseeAmount
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeWinLossByProduct] TO bodbAdminNet
