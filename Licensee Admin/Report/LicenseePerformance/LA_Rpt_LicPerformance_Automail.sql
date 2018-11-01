/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_Automail] 
	@ProductCodes VARCHAR(500) -- not support CB,CO
	, @FromDate		SMALLDATETIME
	, @ToDate		SMALLDATETIME 
AS
/*	Created: 20171122@Parsons
	Task: LicenseeAdmin - Get Licensee Performance Report
	DB: DB052.bodb_licensee

	Revisions:
	 - 20180712@Bruce: Enhance Manage Discount group [#94282]
	 - 20180716@bruce: add new group TEST for credit [#98126]
	 - 20180607@Parsons: Integrate Pragmatic [#94108]

	Example:
	USE bodb_licensee
	DECLARE @ProductCodes		VARCHAR(500)	= 'NG,BA,LC,VS,CS,KN,AGC,GD,VG,BT,MGCLC,MGCRNG,AB,VB,NG2,FW,VS2,LT' 
	DECLARE @FromDate	DATETIME	= '2017-5-01'
	DECLARE @ToDate	DATETIME	= '2017-5-31'

	EXEC [LA_Rpt_LicPerformance_Automail] @ProductCodes, @FromDate, @ToDate	
*/

BEGIN
	SET NOCOUNT ON

	DECLARE 
		@PartyIDs VARCHAR(1000),
		@BaseCurrencyName VARCHAR(10) = 'EUR'
	
	-- get ALL partyIDs exclude 'FDL', 'PIH', '18bb', 'IBC'
	DECLARE @PartyRoot table (PartyId int, PartyName varchar(100), BrandName varchar(100), ParentID int)
	INSERT INTO @PartyRoot
	EXEC LA_PartyListSel 

	DELETE @PartyRoot
	WHERE ParentID IN (0,999)

	SET @PartyIDs = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' 
	FROM @PartyRoot FOR XML PATH(''))

	-- get discount/rebate
	CREATE TABLE #AmountToCompany (
		PartyId			INT,
		ProductId		INT,
		Winloss			MONEY,
		Fee				MONEY,
		Discount		MONEY,
		DiscountRate	MONEY,
		DiscountRemark	NVARCHAR(4000),
		Rebate			MONEY,
		RebateRate		MONEY,
		RebateRemark	NVARCHAR(4000),
		NegativeFee		MONEY,
		Minfee			MONEY,
		IsChargedByMinFee BIT
	)
	INSERT INTO #AmountToCompany(PartyId,ProductId,Winloss,Fee,NegativeFee,Minfee,IsChargedByMinFee,Discount,DiscountRate,DiscountRemark,Rebate,RebateRate,RebateRemark)
	EXEC dbo.LA_AmountToCompanySel @FromDate,@ToDate,@PartyIds,@ProductCodes,@BaseCurrencyName

	-- Region: Party charge info
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		MONEY,
			TypeId		INT,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			Bettype		INT)

	-- ***********************************************************************************************
	-- *** Get ChargeInfo for @PartyIDs 
	-- ***********************************************************************************************
	-- select bettype to avoid duplicated data of MGC

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, Fromdate, Todate, Bettype)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, 
				CASE WHEN ISNULL(ci.isDeposit, 0) = 1 THEN ci.DI_Rate ELSE 0 END,
				ci2.ChargeType, 
				ci.Fromdate, 
				ci.ToDate,	
				CASE WHEN ci.ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END
		FROM	dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
		INNER JOIN dbo.OAS_ChargeInfo ci2 WITH(NOLOCK) ON ci.ChargeID = ci2.ChargeID
		LEFT JOIN Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
	)
	-- End region

	-- **********************************************************************************************
	-- *** Get Exchange info for @BaseCurrencyName
	-- **********************************************************************************************
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

	-- Region: Get Amount by Product
	CREATE	TABLE #TempData (
			PartyId			INT,
			ProductId		INT,
			Turnover		MONEY,
			WinLoss			MONEY,
			AmountToCompany MONEY,
			IsApplyMinFee	BIT)
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId)
	INSERT INTO #TempData (PartyId,Turnover,WinLoss,AmountToCompany,ProductId)
	(
		SELECT	p.PartyId,
				SUM(ISNULL(b.Turnover, 0) * e.Rate),
				SUM(ISNULL(b.MemberWL, 0) * e.Rate),
				SUM(((-ISNULL(b.MemberWL, 0) * p.Rate) - (CASE WHEN b.ProductId = 3 THEN ISNULL(b.CommissionA, 0) ELSE 0 END)) * e.Rate),
				p.ProductId
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
				AND b.CurrencyID <> 20
				AND b.customercategory NOT IN (27, 28)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY p.PartyId, p.ProductId
	)

	-- empty tickets
	INSERT INTO #TempData (PartyId,ProductId,Turnover,WinLoss,AmountToCompany)
	SELECT p.PartyId, p.ProductID,0,0,0
	FROM @PartyChargeInfo p
	GROUP BY p.PartyId, p.ProductID

	-- Sum products
	BEGIN
		DECLARE @SumByProducts TABLE(
			PartyId			INT,
			Turnover		MONEY,
			WinLoss			MONEY,
			AmountToCompany	MONEY,
			ProductId		INT
		)
		-- sum by product
		INSERT INTO @SumByProducts (PartyId,ProductId,Turnover,WinLoss,AmountToCompany)
		SELECT	PartyId
				,ProductId
				,SUM(Turnover) Turnover
				,SUM(WinLoss) WinLoss
				,SUM(AmountToCompany) AmountToCompany
		FROM #TempData
		GROUP BY PartyId, ProductId
	END

	-- Region: Result
	CREATE TABLE #Result (
		PartyId			INT,
		ProductId		INT,
		LicenseeName	VARCHAR(100),
		Turnover		MONEY,
		WinLoss			MONEY,
		AmountToBA		MONEY,
		LicensingFee	MONEY,
		Discount		MONEY,
		Rebate			MONEY
	)

	INSERT INTO #Result (PartyId, ProductId, LicenseeName, LicensingFee, Turnover, WinLoss, AmountToBA, Discount, Rebate)
	SELECT	p.PartyId,
			s.ProductId,
			op.PartyName,
			SUM(CASE WHEN s.ProductId = 3 THEN 0 ELSE ISNULL(r.Fee, s.AmountToCompany) END),
			SUM(s.Turnover),
			SUM(s.WinLoss),
			SUM(CASE WHEN s.ProductId = 3 THEN s.AmountToCompany ELSE 0 END),
			SUM(ISNULL(r.Discount,0)),
			SUM(ISNULL(r.Rebate,0))
	FROM	@PartyRoot p
			INNER JOIN dbo.OAS_Party (NOLOCK) op ON p.PartyId = op.PartyID
			INNER JOIN @SumByProducts s ON p.PartyId = s.PartyId
			LEFT JOIN #AmountToCompany r ON r.PartyId=p.PartyId AND s.ProductId=r.ProductId
	GROUP BY p.PartyId, s.ProductId, op.PartyName

	-- calculate licensing fee
	UPDATE #Result SET LicensingFee = 0 WHERE LicensingFee < 0

	-- Region: Select Data
	;WITH r AS 
	(
		SELECT LicenseeName, 
			SUM(Turnover)	AS Turnover,
			SUM(WinLoss)	AS WinLoss,
			SUM(LicensingFee - Discount - Rebate + AmountToBA) AS LicensingFee
		FROM #Result
		GROUP BY LicenseeName
	)
	SELECT r.LicenseeName, r.Turnover,r.WinLoss,
		CASE WHEN r.WinLoss = 0 THEN 0 ELSE
			ABS((r.LicensingFee/CAST(-r.WinLoss AS DECIMAL(18,5))) * r.Turnover)
		END AS TurnoverOneworks,
		r.LicensingFee
	FROM r
	WHERE r.Turnover != 0 OR r.WinLoss != 0 OR r.LicensingFee != 0
	-- End region

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #Result
	DROP TABLE #AmountToCompany
	-- End region
END
GO

