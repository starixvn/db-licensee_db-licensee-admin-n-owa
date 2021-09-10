/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_GenerateAmountForSoftwareFee]
	@PartyId		INT
	,@BillerId		INT
	,@FromDate		DATETIME
	,@ToDate		DATETIME
	,@ProductCodes	VARCHAR(MAX)
	,@Environment	VARCHAR(50)
	,@ErrCode				INT				= 0		OUTPUT
	,@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
	,@BaseCurrency			VARCHAR(10)		= 'EUR'	OUTPUT
	,@InvoiceTemplateName	VARCHAR(200)	= ''	OUTPUT
AS

/*	Header:
	Created: 2018.10.04 - Parsons
	Task : Generate amount for software fee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20181004@Parsons: Integrate AG setup fee into invoices [#98485]
		- 20190123@Parsons: Improve AG prepayment and discount setting [#104620]
	    - 20190416@Parsons: Integrate-PP-Promotion-Prize [#109014]
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20190911@Bruce: Support Exchange product in invoices [#119846]
		- 20191017@Parsons: Non-peak hour promotion [#119538]
		- 20191209@Parsons: PP tournament [#123958] 
		- 20200505@Parsons: Special handling for INH market [#128570] 
		- 20200714@Parsons: Implement PP Jackpot [RedmineID: #137306] 
		- 20201028@Parsons: Arcadia Gaming - Add Bonus feature [#143597]
		- 20201130@Parsons: Saba.club - Offer Freebet tickets [#141423]
		- 20210201@Parsons: Saba.club - Integrate Slot Game [#147977]
		- 20210314@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
		- 20210408@Parsons: Remove redundant linked server [#FeatureID 152089]
		- 20210306@Danny: AE Sexy - Support Lucky Draw [#152141]
		- 20210720@Sophia: Add Saba Promotion - 17005 - Promotion for Licensee [Redmine: #155388]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate, @TDate DATE = @ToDate
	SELECT  @ErrCode = 0, @ErrMsg = '', @InvoiceTemplateName = ''

	DECLARE	@FinalResult TABLE (ProductId INT, ProductCode VARCHAR(100), ProductName VARCHAR(500)
		,InvoiceAmount MONEY, AmountType TINYINT, Rate MONEY, DeductMonthlyFees MONEY, RemainingAmount MONEY, Remark NVARCHAR(4000))

	-- Get Base Currency
	DECLARE @BaseCurrencyId INT = 6, @BaseCurrencyName VARCHAR(10) = 'EUR' -- default = EUR
	SELECT TOP 1 @BaseCurrencyId = ISNULL(BaseCurrencyId, 6)
	FROM dbo.OAS_PartyBaseCurrency WITH (NOLOCK) WHERE PartyId = @PartyId AND FromDate <= @ToDate AND ToDate >= @FromDate
	
	SELECT @BaseCurrencyName = Code FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE ExchangeId = @BaseCurrencyId
	SELECT @BaseCurrency = @BaseCurrencyName

	-- Check Base Currency Setting
	BEGIN
		-- Individual Min Fee
		IF EXISTS (
			SELECT 1
			FROM dbo.LA_MinFee WITH (NOLOCK)
			WHERE PartyId = @PartyId AND FeeTypeId = 1 AND FromDate <= @TDate AND ToDate >= @FDate
				AND CurrencyId <> @BaseCurrencyId
		)
			SELECT @ErrCode = 1, @ErrMsg = 'Please check the Exchange settings of Payer''s minfee. Exchange of minfee should be the same with Payer''s exchange.'
		
		-- Group Min Fee
		ELSE IF EXISTS (
			SELECT 1
			FROM dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK)
				INNER JOIN dbo.LA_GroupMinFeeHeader h WITH (NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
				INNER JOIN dbo.LA_GroupMinFeeDetail d WITH (NOLOCK) ON a.GroupMinFeeId = d.GroupMinFeeId
			WHERE a.PartyId = @PartyId AND h.FromDate <= @TDate AND h.ToDate >= @FDate
				 AND d.CurrencyId <> @BaseCurrencyId
		)
			SELECT @ErrCode = 3, @ErrMsg = 'Please check the Exchange settings of Payer''s group min fee. Exchange of group min fee must be the same with Payer''s exchange.'
		
		-- Discount
		ELSE IF EXISTS (
			SELECT TOP 1 1
			FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
				INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			WHERE a.PartyId = @PartyId AND h.FromDate <= @TDate AND h.ToDate >= @FDate AND h.DiscountGroupType <> 2 -- 2 = rebate
				AND h.CurrencyId <> @BaseCurrencyId
			ORDER BY h.ToDate DESC -- latest discount group
		)
			SELECT @ErrCode = 2, @ErrMsg = 'Please check the Exchange settings of Payer''s discount. Exchange of discount must be the same with Payer''s exchange.'
		ELSE
			SELECT @ErrCode = 0, @ErrMsg = ''
	END

	IF @ErrCode = 0
	BEGIN
		-- Get Invoice Template
		SELECT TOP 1 @InvoiceTemplateName = t.InvTemplateName
		FROM dbo.LA_InvoiceSetting i WITH (NOLOCK)
			INNER JOIN dbo.LA_InvoiceTemplate t WITH (NOLOCK) ON i.InvTempId = t.InvTemplateId
		WHERE i.FromPartyId = @PartyId AND i.ToPartyId = @BillerId
				AND i.InvTypeId = 1 -- Software Fee

		-- Get Licensing Fee Data
		DECLARE @PartyIds VARCHAR(MAX) = CONVERT(VARCHAR(MAX), @PartyId)
		DECLARE @Result TABLE
		(
			PartyId INT, ProductId INT, ProductCode VARCHAR(10), LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
			,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
		)
		INSERT INTO @Result
		(
			PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
			,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
		)
		EXEC dbo.LA_AmountToCompanyByProduct
			@PartyIds = @PartyIds
			,@ProductCodes = @ProductCodes
			,@FromDate = @FromDate
			,@ToDate = @ToDate
			,@LicensingFeeTypeIds = '0,-1,1,2,3,4,5' -- Contribution, Prize, ...
			,@BaseCurrencyName = @BaseCurrencyName

		INSERT INTO @FinalResult (ProductId, ProductCode, ProductName, InvoiceAmount, AmountType, Rate, Remark)
		SELECT p.ProductId, p.ProductPrefix, p.ProductName, d.InvoiceAmount, d.AmountType, d.Rate, d.Remark
		FROM @Result r
			INNER JOIN dbo.LA_f_Products3rd('') p ON r.ProductId = p.ProductId
			CROSS APPLY (
				SELECT Discount AS InvoiceAmount, CONVERT(TINYINT, 4) AS AmountType, DiscountRate AS Rate, DiscountRemark AS Remark WHERE Discount > 0 -- Discount
				--UNION ALL SELECT Rebate, 6, RebateRate, RebateRemark WHERE Rebate > 0 -- Rebate
				UNION ALL SELECT LicensingFee + ExtraAmount, 1, NULL, NULL -- Software Fee
			) d
		WHERE r.LicensingFeeTypeId = 0 AND r.ProductId <> 37 -- SB Promotion

		-- SB Promotion
		IF EXISTS (SELECT 1 FROM @FinalResult WHERE AmountType = 1 AND ProductId = 0)
			INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, AmountType, InvoiceAmount, RemainingAmount)
			SELECT 0, '', '', 29, LicensingFee, 0 FROM @Result WHERE ProductId = 37 AND LicensingFee > 0

		-- Prize, Contribution, Promotion, ...
		INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, InvoiceAmount, RemainingAmount, AmountType)
		SELECT 0, '', '', SUM(ExtraAmount), 0
			,CASE
				WHEN ProductId = 32 AND LicensingFeeTypeId = 1 THEN 31 -- Contribution
				WHEN ProductId = 32 AND LicensingFeeTypeId = 2 THEN 32 -- JackpotPrize
				WHEN ProductId = 32 AND LicensingFeeTypeId = 3 THEN 30 -- Prize
				WHEN ProductId = 42 AND LicensingFeeTypeId = 1 THEN 35 -- Contribution
				WHEN ProductId = 42 AND LicensingFeeTypeId = 2 THEN 36 -- JackpotPrize
				WHEN ProductId = 42 AND LicensingFeeTypeId = 3 THEN 34 -- Prize
				WHEN ProductId = 66 AND LicensingFeeTypeId = 1 THEN 40 -- Contribution
				WHEN ProductId = 66 AND LicensingFeeTypeId = 2 THEN 39 -- JackpotPrize
				WHEN ProductId = 66 AND LicensingFeeTypeId = 3 THEN 38 -- Prize
				WHEN ProductId = 34 AND LicensingFeeTypeId = 4 THEN 33 -- Bonus
				WHEN ProductId = 37 AND LicensingFeeTypeId = 5 THEN 37 -- Lucky Draw
				END
		FROM @Result
		WHERE ProductId IN (32, 34, 37, 42, 66) AND LicensingFeeTypeId > 0
		GROUP BY
			CASE
				WHEN ProductId = 32 AND LicensingFeeTypeId = 1 THEN 31 -- Contribution
				WHEN ProductId = 32 AND LicensingFeeTypeId = 2 THEN 32 -- JackpotPrize
				WHEN ProductId = 32 AND LicensingFeeTypeId = 3 THEN 30 -- Prize
				WHEN ProductId = 42 AND LicensingFeeTypeId = 1 THEN 35 -- Contribution
				WHEN ProductId = 42 AND LicensingFeeTypeId = 2 THEN 36 -- JackpotPrize
				WHEN ProductId = 42 AND LicensingFeeTypeId = 3 THEN 34 -- Prize
				WHEN ProductId = 66 AND LicensingFeeTypeId = 1 THEN 40 -- Contribution
				WHEN ProductId = 66 AND LicensingFeeTypeId = 2 THEN 39 -- JackpotPrize
				WHEN ProductId = 66 AND LicensingFeeTypeId = 3 THEN 38 -- Prize
				WHEN ProductId = 34 AND LicensingFeeTypeId = 4 THEN 33 -- Bonus
				WHEN ProductId = 37 AND LicensingFeeTypeId = 5 THEN 37 -- Lucky Draw
				END

		-- AMF, Prepayment and AGPrepayment
		BEGIN
			-- AMF & AG Prepayment
			UPDATE f
			SET f.DeductMonthlyFees = r.LicensingFee, f.RemainingAmount = r.GrossLicensingFee
			FROM @FinalResult f
				INNER JOIN @Result r ON f.ProductId = r.ProductId
			WHERE f.AmountType = 1 AND r.LicensingFeeTypeId = -1

			-- Prepayment
			IF EXISTS (SELECT 1 FROM @FinalResult WHERE AmountType = 1)
				INSERT INTO @FinalResult(ProductId, ProductCode, ProductName, AmountType, InvoiceAmount, RemainingAmount)
				SELECT 0, '' , '' , 24, 0, GrossLicensingFee
				FROM @Result WHERE ProductId = -99 AND LicensingFeeTypeId = -1
		END
	END

	-- Return data
	SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType, Rate, DeductMonthlyFees, RemainingAmount, Remark FROM @FinalResult
	ORDER BY AmountType, ProductId
END
GO