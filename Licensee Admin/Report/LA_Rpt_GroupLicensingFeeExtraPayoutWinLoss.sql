/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet,bodbLicenseeNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GroupLicensingFeeExtraPayoutWinLoss]
	@PartyIDs				VARCHAR(1000),
	@ProductCodes			VARCHAR(1000) = 'PP,SBC',
	@FromDate				SMALLDATETIME,
	@ToDate					SMALLDATETIME
AS

/*  Created: Mason.Nguyen
	Date: 2021-02-23
	DB: DB052.bodb_licensee

	Revisions:
	   - 20210223@Mason: Group Licensing Fees Report - Add Jackpot Information [#148030]	
*/

BEGIN
	DECLARE @ChargeInfo TABLE(ChargeID INT, PartyID INT, LicenseeID INT, ProductID INT, Rate MONEY, FromDate DATE, ToDate DATE)
	INSERT INTO @ChargeInfo(ChargeID, PartyID, LicenseeID, ProductID, Rate, FromDate, ToDate)
	SELECT DISTINCT ChargeID, PartyID, LicenseeID, ProductID, CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END, FromDate, ToDate		
	FROM dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1)

	DECLARE @Data AS TABLE(rptDate DATE, PartyId INT, ProductId INT, CurrencyId INT, Turnover MONEY, BetCount INT, CustomerWL MONEY, LicenseeWL MONEY,
						Contribution MONEY, ServiceFee MONEY, JackpotPrize MONEY, FreeBetAmount MONEY, PromotionPrize MONEY, LicensingFee MONEY)

	-- PP
	IF EXISTS (SELECT 1 FROM LA_f_Products3rd(@ProductCodes) WHERE ProductPrefix = 'PP')
	BEGIN
		DECLARE @PP_Contribution SMALLINT = 4297,
			@PP_JackpotPrize SMALLINT = 4298,
			@PP_Tournament SMALLINT = 4299,
			@PP_PromotionPrize SMALLINT = 4300

		;WITH cte_Data_PP AS(
			SELECT b.rptDate, b.SiteID, b.ProductID, b.CurrencyId,
				SUM(CASE WHEN b.Bettype NOT IN(@PP_Tournament, @PP_PromotionPrize, @PP_Contribution, @PP_JackpotPrize) THEN ISNULL(b.BetCount, 0) ELSE 0 END) AS BetCount,
				SUM(CASE WHEN b.Bettype NOT IN(@PP_Tournament, @PP_PromotionPrize, @PP_Contribution, @PP_JackpotPrize) THEN ISNULL(b.Turnover, 0) ELSE 0 END) AS Turnover,
				SUM(CASE WHEN b.Bettype NOT IN(@PP_Tournament, @PP_PromotionPrize, @PP_Contribution, @PP_JackpotPrize) THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS CustomerWL,
				SUM(CASE WHEN b.Bettype NOT IN(@PP_Tournament, @PP_PromotionPrize, @PP_Contribution, @PP_JackpotPrize) THEN ISNULL(-b.MemberWL, 0) ELSE 0 END) AS LicenseeWL,
				SUM(CASE WHEN b.Bettype = @PP_Contribution THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AS Contribution,
				SUM(CASE WHEN b.Bettype = @PP_JackpotPrize THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS JackpotPrize,
				SUM(CASE WHEN b.Bettype IN (@PP_PromotionPrize, @PP_Tournament) THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS PromotionPrize
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK)
			INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			WHERE b.ProductID = 32
			GROUP BY b.SiteID, b.ProductID, b.CurrencyId, b.rptDate)

		INSERT INTO @Data(rptDate, ProductId, PartyId, CurrencyId, Turnover, BetCount, CustomerWL, LicenseeWL, Contribution, JackpotPrize, PromotionPrize, ServiceFee, LicensingFee)
		SELECT c.rptDate, c.ProductID AS ProductId, 
			ci.PartyID AS PartyId, 
			c.CurrencyId AS CurrencyId,
			SUM(c.Turnover) AS Turnover,
			SUM(c.BetCount)	AS BetCount,
			SUM(c.CustomerWL) AS CustomerWL,
			SUM(c.LicenseeWL) AS LicenseeWL,
			SUM(c.Contribution)	AS Contribution,
			SUM(c.JackpotPrize)	AS JackpotPrize,
			SUM(c.PromotionPrize) AS PromotionPrize,
			SUM((c.LicenseeWL - c.Contribution) * ci.Rate) AS ServiceFee,
			SUM((c.LicenseeWL - c.Contribution) * ci.Rate + c.Contribution - c.PromotionPrize - c.JackpotPrize) AS LicensingFee
		FROM cte_Data_PP c
		INNER JOIN @ChargeInfo ci ON c.SiteID = ci.LicenseeID AND c.ProductID = ci.ProductID
		GROUP BY ci.PartyID, c.ProductID, c.CurrencyId, c.rptDate
	END

	-- SBC
	IF EXISTS (SELECT 1 FROM LA_f_Products3rd(@ProductCodes) WHERE ProductPrefix = 'SBC')
	BEGIN
		DECLARE	@SBC_Contribution SMALLINT = 1698,
				@SBC_Jackpot SMALLINT = 1699,
				@FreeBetsTicketType SMALLINT = 2

		;WITH cte_Data_SBC AS(
			SELECT b.rptDate, b.SiteID, b.ProductID, b.CurrencyId,
				SUM(CASE WHEN ISNULL(b.TicketType,0) = @FreeBetsTicketType OR b.Bettype IN (@SBC_Contribution, @SBC_Jackpot) THEN 0 ELSE ISNULL(b.betcount, 0) END) AS BetCount,
				SUM(CASE WHEN ISNULL(b.TicketType,0) = @FreeBetsTicketType OR b.Bettype IN (@SBC_Contribution, @SBC_Jackpot) THEN 0 ELSE ISNULL(b.turnover, 0) END) AS Turnover,
				SUM(CASE WHEN ISNULL(b.TicketType,0) = @FreeBetsTicketType OR b.Bettype IN (@SBC_Contribution, @SBC_Jackpot) THEN 0 ELSE ISNULL(b.MemberWL, 0) END) AS CustomerWL,
				SUM(CASE WHEN ISNULL(b.TicketType,0) = @FreeBetsTicketType OR b.Bettype IN (@SBC_Contribution, @SBC_Jackpot) THEN 0 ELSE ISNULL(-b.MemberWL, 0) END) AS LicenseeWL,
				SUM(CASE WHEN b.Bettype IN (@SBC_Contribution) THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AS Contribution,
				SUM(CASE WHEN b.Bettype IN (@SBC_Jackpot) THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS JackpotPrize,
				SUM(CASE WHEN ISNULL(b.TicketType, 0) = @FreeBetsTicketType THEN ISNULL(b.MemberWL, 0) ELSE 0 END) AS FreeBetAmount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK)
			INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			WHERE b.ProductID = 42
			GROUP BY b.SiteID, b.ProductID, b.CurrencyId, b.rptDate)

		INSERT INTO @Data(rptDate, ProductId, PartyId, CurrencyId, Turnover, BetCount, CustomerWL, LicenseeWL, Contribution, JackpotPrize, FreeBetAmount, ServiceFee, LicensingFee)
		SELECT c.rptDate, c.ProductID AS ProductId, 
			ci.PartyID AS PartyId, 
			c.CurrencyId AS CurrencyId,
			SUM(c.Turnover)		 AS Turnover,
			SUM(c. BetCount)	 AS BetCount,
			SUM(c.CustomerWL)	 AS CustomerWL,
			SUM(c.LicenseeWL)	 AS LicenseeWL,
			SUM(c.Contribution)	 AS Contribution,
			SUM(c.JackpotPrize)	 AS JackpotPrize,
			SUM(c.FreeBetAmount) AS FreeBetAmount,
			SUM((c.LicenseeWL - c.Contribution) * ci.Rate) AS ServiceFee,
			SUM((c.LicenseeWL - c.Contribution) * ci.Rate + c.Contribution - c.JackpotPrize - c.FreeBetAmount) AS LicensingFee
		FROM cte_Data_SBC c
		INNER JOIN @ChargeInfo ci ON c.SiteID = ci.LicenseeID AND c.ProductID = ci.ProductID
		GROUP BY ci.PartyID, c.ProductID, c.CurrencyId, c.rptDate
	END

	SELECT 
		-- Original
		prd.ProductName			AS ProductName,
		prd.ProductPrefix		AS ProductCode,
		d.PartyId				AS PartyId,
		p.PartyName				AS PartyName,
		d.CurrencyId			AS Currency,
		e.Code					AS CurrencyName,
		SUM(d.Turnover)			AS Turnover,
		SUM(d.BetCount)			AS Betcount,
		SUM(d.CustomerWL)		AS MemberWinloss,
		SUM(d.LicenseeWL)		AS LicenseeWL,
		SUM(d.Contribution)		AS Contribution,
		SUM(d.JackpotPrize)		AS JackpotPrize,
		SUM(d.FreeBetAmount)	AS FreeBetAmount,
		SUM(d.ServiceFee)		AS LicenseeChargeRate,
		SUM(d.LicensingFee)		AS Company,
		SUM(d.PromotionPrize)	AS WinningPrize,
		-- Base on EUR
		SUM(d.Turnover * e.BaseCurrencyRate)		AS TurnoverBase,
		SUM(d.CustomerWL * e.BaseCurrencyRate)		AS MemberWinlossBase,
		SUM(d.LicenseeWL * e.BaseCurrencyRate)		AS LicenseeWLBase,
		SUM(d.Contribution * e.BaseCurrencyRate)	AS ContributionBase,
		SUM(d.JackpotPrize * e.BaseCurrencyRate)	AS JackpotPrizeBase,
		SUM(d.FreeBetAmount * e.BaseCurrencyRate)	AS FreeBetAmountBase,
		SUM(d.ServiceFee * e.BaseCurrencyRate)		AS LicenseeChargeRateBase,
		SUM(d.LicensingFee * e.BaseCurrencyRate)	AS CompanyBaseCurrency,
		SUM(d.PromotionPrize * e.BaseCurrencyRate)	AS WinningPrizeBase
	FROM @Data d 
	INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON d.PartyId = p.PartyID
	INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'EUR') e ON d.CurrencyId = e.ExchangeId AND e.exchangedate = d.rptDate
	INNER JOIN LA_f_Products3rd(@ProductCodes) prd ON prd.ProductId = d.ProductId
	GROUP BY prd.ProductName, prd.ProductPrefix, d.PartyId, p.PartyName, d.CurrencyId, e.Code
END