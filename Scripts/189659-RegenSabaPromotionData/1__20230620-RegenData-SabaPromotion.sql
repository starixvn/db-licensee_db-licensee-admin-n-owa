/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20230620@Danny
	DB: DBLIC-bodb_Licensee
	Task: Insert Data Saba Promotion
	ProductId = 37
*/
USE bodb_LicenseeReport
GO

SET NOCOUNT ON 
SET ANSI_WARNINGS OFF

IF OBJECT_ID (N'dbo.rptLicPerformanceAnalysis_regen_UAT', N'U') IS NULL  
BEGIN
	CREATE TABLE rptLicPerformanceAnalysis_regen_UAT -- drop later when testing done
	(
		[RecordId] [int] IDENTITY(1,1) NOT NULL,
		[ReportDate] [date] NOT NULL,
		[SiteId] [int] NOT NULL,
		[ProductId] [int] NOT NULL,
		[CurrencyId] [int] NOT NULL,
		[Turnover] [money] NULL,
		[BetCount] [int] NULL,
		[LicenseeWinloss] [money] NULL,
		[LicensingFee] [money] NULL,
		[Discount] [money] NULL,
		[Rebate] [money] NULL,
		[TurnoverNoDraw] [money] NULL,
		[IsBillingCurrency] [bit] NOT NULL,
		[Adjustment] [money] NULL
	)

	CREATE UNIQUE NONCLUSTERED INDEX [IX_rptLicPerformanceAnalysis_regen_UAT] ON [dbo].[rptLicPerformanceAnalysis_regen_UAT]
	(
		[ReportDate] ASC,
		[SiteId] ASC,
		[ProductId] ASC,
		[CurrencyId] ASC
	)
END

DECLARE @StartDate DATETIME = '2022-12-01'
DECLARE @EndDate DATETIME = EOMONTH(@StartDate)
DECLARE @PartyIDs VARCHAR(MAX), @CurrencyName VARCHAR(10), @ExchangeID INT

DECLARE @CurTab TABLE (BaseCurrencyName VARCHAR(10), ExchangeID INT, ID INT identity (1,1))
INSERT INTO @CurTab (BaseCurrencyName, ExchangeID)
SELECT CASE WHEN ExchangeId = 142 THEN 'USDT' ELSE Code END , ExchangeID
FROM bodb02.dbo.Exchange WITH(NOLOCK) WHERE ExchangeId IN (2,3,6,12,13,142)

DECLARE @i INT = 1

DECLARE @Result TABLE
(
	PartyId INT, ProductId INT, ProductCode VARCHAR(10), LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
	,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
	,Winloss MONEY, Turnover MONEY, TurnoverNoDraw MONEY, BetCount INT, BaseCurrencyId INT, ExtraInfo NVARCHAR(4000)
)

WHILE @StartDate <= '2023-06-01'
BEGIN
	SET @i = 1
	print('gen---' + CAST (@StartDate AS VARCHAR(50)))
	WHILE  EXISTS (SELECT TOP 1 1 FROM @CurTab WHERE ID =@i)
	BEGIN
		-- Get @PartyIDs
		SElECT  @PartyIDs = '', @CurrencyName = BaseCurrencyName , @ExchangeID = ExchangeID FROM @CurTab WHERE ID = @i
		DELETE FROM @Result

		SELECT @PartyIDs = STRING_AGG(op.PartyID,',')
		FROM dbo.rptLicPerformanceAnalysis r WITH(NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_Party op WITH(NOLOCK) ON op.OldRefID = r.SiteId AND op.PartyType = 1
		WHERE r.ProductId = 0 AND r.ReportDate = @StartDate AND r.CurrencyId = @ExchangeID

		IF (@PartyIDs IS NOT NULL)
		BEGIN
			INSERT INTO @Result
			(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
			)
			EXEC bodb_licensee.dbo.LA_AmountToCompanyByProduct
				@PartyIds = @PartyIds
				,@ProductCodes = 'SB'
				,@FromDate = @StartDate
				,@ToDate = @EndDate
				,@BaseCurrencyName = @CurrencyName

			DELETE FROM @Result WHERE (ProductId = 0 AND  @StartDate = '2023-06-01') -- get 37,74 
									OR (ProductId IN (0, 37) AND  @StartDate < '2023-06-01') -- get 74

			INSERT INTO rptLicPerformanceAnalysis_regen_UAT (ReportDate, SiteId, ProductId, CurrencyId, LicensingFee, IsBillingCurrency)
			SELECT @StartDate, op.OldRefID, r.ProductId, @ExchangeID, CASE WHEN  r.ProductId = 74 THEN  ISNULL(r.ExtraAmount,0) ELSE  ISNULL(r.LicensingFee,0) + ISNULL(r.ExtraAmount,0) END , 0
			FROM @Result r
			INNER JOIN  bodb_licensee.dbo.OAS_Party op WITH(NOLOCK) ON r.PartyId = op.PartyId
			WHERE ISNULL(r.LicensingFee,0) <> 0 OR  ISNULL(r.ExtraAmount,0) <> 0
		END

		SELECT @i = @i + 1
	END

	-- Next turn
	SELECT @StartDate = DATEADD(MONTH,1, @StartDate)
	SELECT @EndDate = EOMONTH(@StartDate)

END


--select * from rptLicPerformanceAnalysis_regen_UAT with(nolock) order by ReportDate, siteiD, CurrencyId
--truncate table rptLicPerformanceAnalysis_regen_UAT