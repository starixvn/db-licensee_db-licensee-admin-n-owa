/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceAmountGenerate]
	@PartyId			INT
	,@BillerId			INT
	,@InvoiceTypeId		INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@ProductCodes		VARCHAR(MAX)
	,@Environment		VARCHAR(50)
	,@ErrCode					INT				= 0		OUTPUT
	,@ErrMsg					NVARCHAR(1000)	= ''	OUTPUT
	,@BaseCurrency				VARCHAR(10)		= 'EUR'	OUTPUT
	,@InvoiceTemplateName		VARCHAR(200)	= ''	OUTPUT
	,@HostingFeesExchangeName	VARCHAR(20)		= ''	OUTPUT
	,@HostingFeesExchangeRate	FLOAT			= 0		OUTPUT
	,@HostingFeesAmount			MONEY			= 0		OUTPUT
	,@HostingFeesMaxPCU			INT				= 0		OUTPUT
	,@IsWaived					BIT				= 0		OUTPUT
AS

/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20150806@Bravo.Tran: Invoice Amount - Generate
		- 20150922@Bravo.Tran: Invoice Amount - Fix bug wrong Total amount under Discount.
		- 20151109@Bravo.Tran: Invoice Amount - Enhance prorate min fee.
		- 20160627@Bravo.Tran: Invoice Amount - Hosting Fess amount.
		- 20160719@Bruce.Bui: Adding hosting fees extra info.
		- 20160927@Bruce.Bui: Get MaxPCU case full month waive
		- 20161024@Bruce.Bui: Add new discount type = 3
		- 20160927@Bruce.Bui: Get MaxPCU case full month waive
		- 20161104@Scofield.Huynh: Update for CB
		- 20170306@bruce: include BA amount =0 [RedmindID: #72806]
		- 20170307@Scofield: include amount = 0 for all products [RedmindID: #72806]
		- 20170403@Scofield: update for Cashout [RedmindID: #73310]
		- 20170404@Harper: using new sum table for Cashout Product [RedmindID: #73310]
		- 20170505@Bruce: Correct Product name in Description [RedmindID: #75950]
		- 20170718@Bruce: restructure invoice db [RedmindID: #79905]
		- 20170721@Scofield: Update Amount Type [#79905]
		- 20170721@Bruce: Calculate AMF amount [#76410]
		- 20171002@Bruce: add environment to parameter list [#84038]
		- 20171027@Bruce: show individual discount by product [#85256]		
		- 20171113@Bruce: Modified error message [RedmineID: #84163]
		- 20171220@Parsons: increase length for variables [#88197]
		- 20180110@Bruce: deduct against invoice [#87039]
		- 20180419@Scofield: update CB for FreePlay [#93907]
		- 20180525@Scofield: Incorporate 9wickets' data [#94950]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180712@Bruce: Enhance Manage Discount group [#94282]
		- 20181002@Parsons: Integrate AG setup fee into invoices [#98485]
		- 20200228@Parsons: Support-HID-currency [#128856]
		- 20200406@Parsons: Issue rebate worksheet [#131874]
		- 20201202@Parsons: Add more condition to get only one rebate setting at the one time [#142345]
		- 20210314@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
		- 20210408@Parsons: Remove redundant linked server [#FeatureID 152089]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate, @TDate DATE = @ToDate
	SELECT  @ErrCode = 0, @ErrMsg = '', @InvoiceTemplateName = '', @BaseCurrency = 'EUR' -- default
			,@HostingFeesExchangeName = '', @HostingFeesExchangeRate = 0, @HostingFeesAmount = 0, @HostingFeesMaxPCU = 0, @IsWaived = 0

	DECLARE	@FinalResult TABLE (ProductId INT, ProductCode VARCHAR(100), ProductName VARCHAR(500)
		,InvoiceAmount MONEY, AmountType TINYINT, Rate MONEY, DeductMonthlyFees MONEY, RemainingAmount MONEY, Remark NVARCHAR(4000))

	-- Get Base Currency
	DECLARE @BaseCurrencyId INT = 6
	SELECT TOP 1 @BaseCurrencyId = BaseCurrencyId
	FROM dbo.OAS_PartyBaseCurrency WITH (NOLOCK) WHERE PartyId = @PartyId AND FromDate <= @ToDate AND ToDate >= @FromDate
	
	SELECT @BaseCurrency = Code FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE ExchangeId = @BaseCurrencyId

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

		--IF @InvoiceTypeId = 6 -- Hosting Fees --> check later
		IF @InvoiceTypeId = 3 -- Rebate
		BEGIN
			SET @ProductCodes = NULL
			SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode
			FROM (
				SELECT CASE WHEN p.ProductId = 0 THEN 'SB' ELSE pd.ProductPrefix END AS ProductCode
				FROM dbo.LA_DiscountGroupAssignment a WITH (NOLOCK)
					INNER JOIN dbo.LA_DiscountGroupHeader h WITH (NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
					INNER JOIN dbo.LA_DiscountGroupProduct p WITH (NOLOCK) ON a.DiscountGroupId = p.DiscountGroupId
					LEFT JOIN dbo.Product3rd pd WITH(NOLOCK) ON p.ProductId = pd.ProductId
				WHERE a.PartyId = @PartyId AND h.FromDate <= @TDate AND h.ToDate >= @FDate
					AND h.DiscountGroupType = 2 -- Rebate
			) r
			WHERE ProductCode IS NOT NULL

			IF ISNULL(@ProductCodes, '') = ''
				SELECT @ErrCode = 1, @ErrMsg = 'There is no setting for Rebate in the Rebate Group. Please set it before proceeding further.'
		END
	END

	IF @ErrCode = 0
	BEGIN
		-- Get Invoice Template
		SELECT TOP 1 @InvoiceTemplateName = t.InvTemplateName
		FROM dbo.LA_InvoiceSetting i WITH (NOLOCK)
			INNER JOIN dbo.LA_InvoiceTemplate t WITH (NOLOCK) ON i.InvTempId = t.InvTemplateId
		WHERE i.FromPartyId = @PartyId AND i.ToPartyId = @BillerId
				AND i.InvTypeId = @InvoiceTypeId

		IF @InvoiceTypeId = 6 -- Hosting Fees
		BEGIN
			DECLARE @Exchange TABLE (ExchangeId INT, Code VARCHAR(20), Rate FLOAT)
			INSERT INTO @Exchange (ExchangeId, Code, Rate)
			SELECT ExchangeId, Code, BaseCurrencyRate FROM bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, @BaseCurrency)
			
			DECLARE @HostingFee TABLE (SettingType TINYINT, ProductName VARCHAR(500), BaseCurrencyId INT, NoOfDate INT, Amount MONEY, CurrencyId INT)
			INSERT INTO @HostingFee (SettingType, ProductName, BaseCurrencyId, NoOfDate, Amount, CurrencyId)
			SELECT s.SettingType, s.ProductName, s.BaseCurrencyId, DATEDIFF(DAY, s.FromDate, s.ToDate) + 1, s.Amount, CurrencyId
			FROM (
				SELECT s.SettingType, s.ProductName, s.BaseCurrencyId, d.Amount, d.BaseCurrencyId AS CurrencyId
					,CASE WHEN s.FromDate < @FromDate THEN @FromDate ELSE s.FromDate END AS FromDate
					,CASE WHEN s.ToDate > @ToDate THEN @ToDate ELSE s.ToDate END AS ToDate
					,ROW_NUMBER() OVER(PARTITION BY s.SettingType ORDER BY s.FromDate DESC) AS RN
				FROM dbo.LA_HostingFeesSetting s WITH (NOLOCK)
					LEFT JOIN dbo.LA_HostingFees f WITH (NOLOCK) ON s.HostingFeesId = f.HostingFeesId
					LEFT JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON f.HostingFeesId = d.HostingFeesId AND f.HostingFeesTypeId = 1 -- Fixed
				WHERE s.FromParty = @PartyId AND @FromDate <= s.ToDate AND @ToDate >= s.FromDate
			) s
			WHERE s.RN = 1 AND DATEDIFF(DAY, s.FromDate, s.ToDate) >= 0

			IF NOT EXISTS (SELECT 1 FROM @HostingFee WHERE SettingType = 1)
				SELECT @ErrCode = 81, @ErrMsg = 'There is no hosting fees charge rate settings!'
			ELSE IF EXISTS (SELECT 1 FROM @HostingFee WHERE SettingType = 1 AND BaseCurrencyId <> @BaseCurrencyId)
				SELECT @ErrCode = 80, @ErrMsg = 'Please check the Exchange settings of Hosting Charge Rate. Exchange of the setting must be the same with Payer'' exchange'
			ELSE
			BEGIN
				SELECT @HostingFeesExchangeName = e.Code, @HostingFeesExchangeRate = e.Rate, @HostingFeesAmount = h.Amount
				FROM @HostingFee h
					INNER JOIN @Exchange e ON h.CurrencyId = e.ExchangeId AND h.SettingType = 1

				IF EXISTS (SELECT 1 FROM @HostingFee WHERE SettingType = 2)
					SET @IsWaived = 1

				UPDATE h
				SET h.Amount = h.Amount * e.Rate * ISNULL((1.0 * (h.NoOfDate - w.NoOfDate) / h.NoOfDate), 1.0)
				FROM @HostingFee h
					INNER JOIN @Exchange e ON h.CurrencyId = e.ExchangeId
					LEFT JOIN @HostingFee w ON w.SettingType = 2
				WHERE h.SettingType = 1

				INSERT INTO @FinalResult (ProductId, ProductCode, ProductName, InvoiceAmount, AmountType)
				SELECT p.ProductId, p.ProductPrefix, h.ProductName, h.Amount, 8
				FROM @HostingFee h
					INNER JOIN dbo.LA_f_Products3rd('') p ON h.ProductName = p.ProductName
				WHERE h.SettingType = 1
			END
		END
		ELSE IF ISNULL(@ProductCodes, '') <> ''
		BEGIN
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
				,@BaseCurrencyName = @BaseCurrency

			INSERT INTO @FinalResult (ProductId, ProductCode, ProductName, InvoiceAmount, AmountType, Rate, Remark)
			SELECT p.ProductId, p.ProductPrefix, p.ProductName, d.InvoiceAmount, d.AmountType, d.Rate, d.Remark
			FROM @Result r
				INNER JOIN dbo.LA_f_Products3rd('') p ON r.ProductId = p.ProductId
				CROSS APPLY (
					SELECT Discount AS InvoiceAmount, CONVERT(TINYINT, 4) AS AmountType, DiscountRate AS Rate, DiscountRemark AS Remark WHERE Discount > 0 -- Discount
					UNION ALL SELECT Rebate, 6, RebateRate, RebateRemark -- Rebate
					UNION ALL SELECT LicensingFee, 1, NULL, NULL -- Software Fee
				) d
			WHERE r.ProductId <> 37 -- SB Promotion
				AND (
					@InvoiceTypeId <> 3
					OR (@InvoiceTypeId = 3 AND d.AmountType = 6) -- Rebate
					OR (@InvoiceTypeId NOT IN (3, 10) AND r.ProductId <> -1)
				)

			-- Sum data for Rebate
			IF EXISTS (SELECT 1 FROM @FinalResult WHERE AmountType = 6 HAVING COUNT(1) > 1)
			BEGIN
				INSERT INTO @FinalResult (InvoiceAmount, AmountType, Rate, Remark, ProductId, ProductCode, ProductName)
				SELECT SUM(InvoiceAmount), 6, MAX(Rate), MAX(Remark), -1
					,STUFF((SELECT ',' + f.ProductCode
							FROM @FinalResult f WHERE f.AmountType = 6 --AND f.Rate = r.Rate AND f.Remark = r.Remark
							FOR XML PATH('')), 1, 1, '')
					,STUFF((SELECT ',' + f.ProductName
							FROM @FinalResult f WHERE f.AmountType = 6 --AND f.Rate = r.Rate AND f.Remark = r.Remark
							FOR XML PATH('')), 1, 1, '')
				FROM @FinalResult r
				--GROUP BY Rate, Remark

				DELETE @FinalResult WHERE AmountType = 6 AND ProductId >= 0
			END

			IF @InvoiceTypeId = 10 -- sum data
				INSERT INTO @FinalResult (ProductId, AmountType, Rate, Remark, ProductCode, ProductName, InvoiceAmount)
				SELECT -1, r.AmountType, r.Rate, r.Remark
					,STUFF((SELECT ',' + ProductCode
							FROM @FinalResult f WHERE f.AmountType = r.AmountType AND f.Rate = r.Rate AND f.Remark = r.Remark
							FOR XML PATH('')), 1, 1, '')
					,STUFF((SELECT ',' + ProductName
							FROM @FinalResult f WHERE f.AmountType = r.AmountType AND f.Rate = r.Rate AND f.Remark = r.Remark
							FOR XML PATH('')), 1, 1, '')
					,SUM(InvoiceAmount)
				FROM @FinalResult r
				WHERE r.AmountType > 1
				GROUP BY r.AmountType, r.Rate, r.Remark
		END
	END

	-- Return data
	IF @ErrCode <> 0
	BEGIN
		IF @InvoiceTypeId = 6 -- Hosting Fee
			SELECT ProductId, ProductCode, ProductName, InvoiceAmount, InvoiceAmount AS WithoutWaivedAmount, AmountType FROM @FinalResult
		ELSE
			SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType FROM @FinalResult
	END
	ELSE
		SELECT ProductId, ProductCode, ProductName, InvoiceAmount, AmountType, Rate, DeductMonthlyFees, RemainingAmount, Remark FROM @FinalResult
		ORDER BY AmountType, ProductId
END
GO