/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_StraightDiscountSel]
	@ReportMonth DATE
AS

/*
	Created: 20191007@Bruce
	Task : Get straight discount for sportbook
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20191007@Bruce: Create Sp [#120220]
		- 20200117@Mason: Setup billing terms by Currency  [#120005]
		- 20200512@Parsons: Special handling for INH market [#128570]
		- 20201209@Parsons: Licensee Reconciliation - Change Discount column if licensee has straight rebate [#146328]
		- 20210323@Percy: Support duo base currency [RedmineID: #152089]
		- 20210407@Percy: Support duo base currency - Change code for Collection Summary [RedmineID: #152089]
		- 20211101@Percy: Apply core SP to get Licensing Fee [RedmineID: #162158]
		- 20211212@Percy: Set OddsSpread = 0 if negative value [RedmineID: #165849]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FromDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @ReportMonth), 0)
	DECLARE @ToDate DATE = DATEADD(DAY, -1, DATEADD(MONTH, 1, @FromDate))

	-- Get licensees have SB straight discount
	DECLARE @DiscountSetting TABLE (PartyId INT, BaseCurrencyId INT, BaseCurrencyName VARCHAR(5), LicenseeCode VARCHAR(50), DiscountRate MONEY)
	INSERT INTO @DiscountSetting (PartyId, DiscountRate)
	SELECT a.PartyId, d.Rate
	FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupDetail d WITH (NOLOCK) ON d.DiscountGroupId = h.DiscountGroupId AND d.FromAmount = 0 AND d.ToAmount = 10000000000000 -- straight discount
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON p.DiscountGroupId = h.DiscountGroupId AND p.ProductId = 0 -- SB
		INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId AND a.IsApplyDiscount = 1
	WHERE @ToDate BETWEEN h.FromDate AND h.ToDate
		AND h.DiscountGroupType <> 2 -- 2 = rebate, <> 2 = discount
		AND p.CalculationType IN (1, 10) -- 0 = calculated only, 1 = discount only, 10 = calculated & discount

	UPDATE d
	SET d.BaseCurrencyId = ISNULL(bc.BaseCurrencyId, 6), d.BaseCurrencyName = ISNULL(e.Code, 'EUR'), d.LicenseeCode = ISNULL(UPPER(bc.LicenseeCode), '') + '|' + CONVERT(VARCHAR(50), d.PartyId)
	FROM @DiscountSetting d
		LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON d.PartyId = bc.PartyId
		LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON bc.BaseCurrencyId = e.ExchangeId
	WHERE @ToDate BETWEEN bc.FromDate AND bc.ToDate

	-- Base Exchange Rate
	DECLARE @BaseCurrencyList TABLE (ExchangeId INT, ExchangeName VARCHAR(5))
	INSERT INTO @BaseCurrencyList (ExchangeId, ExchangeName)
	SELECT DISTINCT BaseCurrencyId, BaseCurrencyName FROM @DiscountSetting

	-- Get SB fee
	DECLARE @Result TABLE
	(
		PartyId INT, ProductId INT, ProductCode VARCHAR(10), LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
		,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
	)
	DECLARE @BaseCurrencyId INT, @BaseCurrencyName VARCHAR(5), @PartyIds VARCHAR(MAX)

	WHILE EXISTS (SELECT 1 FROM @BaseCurrencyList)
	BEGIN
		SELECT @BaseCurrencyId = NULL, @BaseCurrencyName = NULL, @PartyIds = NULL
		SELECT TOP 1 @BaseCurrencyId = ExchangeId, @BaseCurrencyName = ExchangeName FROM @BaseCurrencyList
		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(15), PartyId) FROM @DiscountSetting WHERE BaseCurrencyId = @BaseCurrencyId
		
		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
		)
		EXEC dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = 'SB'
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@BaseCurrencyName = @BaseCurrencyName
			
		DELETE @BaseCurrencyList WHERE ExchangeId = @BaseCurrencyId
	END

	-- Return data
	SELECT d.LicenseeCode, d.DiscountRate, r.LicensingFee
	FROM @Result r
		INNER JOIN @DiscountSetting d ON d.PartyId = r.PartyId
	DROP TABLE #Result
	DROP TABLE #tmpData
END
GO