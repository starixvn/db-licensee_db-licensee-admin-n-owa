/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_Rpt_LicPerformance_Alert
	@FromDate DATE,
	@ToDate DATE,
	@ProductCodes VARCHAR(500)
AS
/*	Created: 20181128@Parsons
	Task: LA-Licensee Performance Alert
	DB: DBLIC.bodb_licensee

	Revisions:
		- 20181128@Parsons: LA - Licensee Performance Alert [#104918]

	Param's Explanation:
	EXEC LA_Rpt_LicPerformance_Alert @FromDate = '2018-9-01', @ToDate = '2018-9-30', @ProductCodes = 'SB'
*/
BEGIN
	SET NOCOUNT ON;
	
	DECLARE @BaseCurrencyName VARCHAR(3) = 'EUR'
			,@PrevFromDate DATE = DATEADD(M, -1,  @FromDate)
			,@PrevToDate DATE = DATEADD(M, - 1, @ToDate)

	-- Region Get @Parties 
	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT, OldRefID INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	UPDATE p
	SET OldRefID = p2.OldRefID
	FROM @Parties p
	INNER JOIN dbo.OAS_Party (NOLOCK) p2 ON p.PartyId = p2.PartyId
	-- Endregion Get @Parties 

	-- Region: Get exchange rate info
	-- *** Get Exchange info for @BaseCurrencyName in 2 periods (current period and previous period)
	-- **********************************************************************************************
	DECLARE @Exchange TABLE (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT)

	INSERT INTO @Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	INSERT INTO @Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@PrevFromDate, @PrevToDate, @BaseCurrencyName)
	-- End region: Get exchange rate info
	
	-- Select Result	
	SELECT	p.PartyId, p.PartyName,
			SUM((CASE WHEN MONTH(b.rptDate) = MONTH(@FromDate) THEN b.BetCount ELSE 0 END)) AS BetCount,
			SUM((CASE WHEN MONTH(b.rptDate) = MONTH(@FromDate) THEN 0 ELSE b.BetCount END)) AS PreviousBetCount,
			SUM((CASE WHEN MONTH(b.rptDate) = MONTH(@FromDate) THEN b.Turnover * e.Rate ELSE 0 END)) AS Turnover,
			SUM((CASE WHEN MONTH(b.rptDate) = MONTH(@FromDate) THEN 0 ELSE b.Turnover * e.Rate END)) AS PreviousTurnover
	FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @Parties p ON p.OldRefID = b.SiteID
			INNER JOIN dbo.LA_f_Products3rd(@ProductCodes) pd ON b.ProductID = pd.ProductID
			INNER JOIN @Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
	WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate OR b.rptDate BETWEEN @PrevFromDate AND @PrevToDate)
			AND b.customercategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
			AND p.ParentId IN (1, 9, 11, 98)
	GROUP BY p.PartyId, p.PartyName
END
GO