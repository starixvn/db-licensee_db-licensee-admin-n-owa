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

	-- Region: Get exchange rate info
	DECLARE @Exchange TABLE (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT)

	INSERT INTO @Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End region: Get exchange rate info
	
	-- Select Result	
	SELECT	p.PartyId, p.PartyName,
			SUM(b.BetCount) AS BetCount,
			SUM(b.Turnover * e.Rate) AS Turnover
	FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN dbo.OAS_Party (NOLOCK) p ON p.OldRefID = b.SiteId
			INNER JOIN dbo.LA_f_Products3rd(@ProductCodes) pd ON b.ProductID = pd.ProductID
			INNER JOIN @Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
	WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
			AND b.customercategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
			AND p.PartyType = 1 AND p.PartyName NOT IN ('IBC','18bb', 'EU88')
	GROUP BY p.PartyId, p.PartyName
END
GO