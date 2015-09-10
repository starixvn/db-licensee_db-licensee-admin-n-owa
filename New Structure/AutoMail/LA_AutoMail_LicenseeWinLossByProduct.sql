USE [bodb_Licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_AutoMail_LicenseeWinLossByProduct]	  
	@FromDate		DATETIME,
	@ToDate			DATETIME,	
	@CurrencyName	VARCHAR(10)
	
WITH RECOMPILE
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.06: Invoice Amount - Generate
*/
/*	Example:
	USE bodb_Licensee
	DECLARE @FromDate		DATETIME		= '2015-7-1'
	DECLARE @ToDate			DATETIME		= '2015-7-31'
	DECLARe @CurrencyName	VARCHAR(10)		= 'GBP'
			
	EXEC [LA_AutoMail_LicenseeWinLossByProduct] @FromDate, @ToDate, @CurrencyName
	
*/
BEGIN
	SET NOCOUNT ON
	
	-- Region: Get party charge rate info
	DECLARE @ProductCode VARCHAR(100)= 'SB,NG,RB,VS,LC,CS,KN,AGC,GD,VG'
	DECLARE @PartyIdString VARCHAR(2000)
	SELECT @PartyIdString = COALESCE(@PartyIdString + ', ', '') + CONVERT(VARCHAR(10), PartyId)
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
	WHERE PartyType = 1
	
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
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
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CurrencyName)
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
			ProductId	TINYINT)
	
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,MemberWL,AWinLoss,AComm,ProductId)
	(
	    SELECT	b.SiteID,
				p.PartyId, 
				b.rptDate, 
				b.CurrencyID, 
				SUM(ISNULL(b.MemberWL, 0)) Winloss,
				SUM(ISNULL(b.GrossWL, 0)) AS AWinLoss,
				SUM(ISNULL(b.CommissionA, 0)) AS AComm, 
				b.ProductId
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON b.SiteID = p.OldRefID AND p.PartyType = 1													
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate			
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903)
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, b.ProductId
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
		VG			MONEY  -- VG
	)
	INSERT INTO #LicenseeAmount(GroupName, LicenseeId, PartyId,PartyName)
	SELECT	CASE
				WHEN p.PartyId = 1 THEN 'ONEWorks'
				WHEN p.PartyId = 11 THEN 'Boping'
				WHEN p.PartyId = 98 THEN 'Zelianta'
				ELSE 'Credit' 
			END	AS PartyName,			
			op.OldRefID,
			t.PartyId, 
			t.PartyName
	FROM	@TempPartyList t INNER JOIN @TempPartyList p ON t.ParentId = p.PartyId
			INNER JOIN dbo.OAS_Party op WITH (NOLOCK) ON op.PartyID = t.PartyId
	WHERE	t.ParentId != 0 AND p.PartyId != 98
	
	-- BA	
	;WITH AmountDueBA AS
	(
		SELECT	d.LicenseeId,
				SUM(-(MemberWL + AComm)) Amount
		FROM	#TempData d
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
				SUM(-(MemberWL + AWinloss + AComm)) Amount
		FROM	#TempData d
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
				ISNULL(SUM(CASE WHEN d.ProductId = 12 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS VG
		FROM	#TempData d
				INNER JOIN @PartyChargeInfo ci ON	d.PartyId = ci.PartyId 
													AND ci.ProductId = d.ProductId 
													AND d.rptDate BETWEEN ci.FromDate AND ci.ToDate
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
			VG = a.VG
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
	
	SELECT	l.GroupName,l.PartyName,l.SB,l.RB,l.NG,l.BA,l.LC,l.VS,l.CS, l.KN,l.AGC,l.GD,l.VG
	FROM	#LicenseeAmount l
	
	-- EndRegion
END

GO
GRANT EXECUTE ON [dbo].[LA_AutoMail_LicenseeWinLossByProduct] TO bodbLicenseeNet