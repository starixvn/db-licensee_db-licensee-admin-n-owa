/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_MultipleGenerationTemporaryInvoiceSel]
	@BillerId				INT,
	@InvoiceGeneratingData	NVARCHAR(MAX),
	@FromDate				DATE,
	@ToDate					DATE,
	@Environment			VARCHAR(10)
AS

/*	Header:
	Created: 2021.03.02 - Parsons
	Task : Support a function to export all invoices at once: Generate Multiple Temporary Invoice
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20210302@Parsons: Create new sp [#147006]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20211105@Percy: Fix issue missing Saba Promotion [RedmineID: #159691]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20211207@Percy: Return BrandName [RedmineID: #163800]
		- 20220315@Percy: Separate Sponsorship from Saba Promotion [RedmineID: #167121]
		- 20220506@Percy: Exclude Tier Rebate from Invoice [RedmineID: #1732342]
		- 20201025@Danny: Support USDT as base currency [RedmineID: #177718]
		- 20221213@Danny: Import HideRebateWorksheet Info from Excel template [RedmineID: #181546]
		- 20221226@Danny: Integrate Player tips [#180703]
		- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20230605@Danny: Invoice No should be listed in ascending order by number [RedmineID: #189284]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]
		- 20240410@Danny: Return biller CompanyName & Address1  [Redmine: #194604]

	Param's Explanation:
		@InvoiceGeneratingData:
		'<Root>
			<InvoiceGenerating>
				<InvoiceNumber>123</InvoiceNumber>
				<PartyId>1</PartyId>
				<InvoiceTypeShorten>S</InvoiceTypeShorten>
				<HideRebateWorkSheet>Y</HideRebateWorkSheet>
			</InvoiceGenerating>
		</Root>'
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FinalResult TABLE (PartyId INT, InvoiceHeaderId BIGINT, InvoiceSymbol NVARCHAR(20), InvoiceNumber INT, BillerId INT, InvoiceType TINYINT, InvoicePath NVARCHAR(255), ProductCodes VARCHAR(MAX), LicensingFee MONEY, Discount MONEY, ExtraAmount MONEY, AdjustmentAmount MONEY, AdjustmentNote NVARCHAR(500))
	
	-- Get Product List
	BEGIN
		DECLARE @Products TABLE (GroupProductId INT, ProductId INT, ProductCode VARCHAR(50))
		INSERT INTO @Products (GroupProductId, ProductId, ProductCode)
		SELECT 0, 0, 'SB'
		UNION ALL
		SELECT -37, -37, 'SPR(CS)'
		UNION ALL
		SELECT ISNULL(g.GroupProductId, p.ProductId), p.ProductId, p.ProductPrefix
		FROM dbo.Product3rd p WITH (NOLOCK)
			LEFT JOIN dbo.LA_f_GroupProduct('',@FromDate,@ToDate) g ON p.ProductId = g.ProductId
		WHERE p.ProductId NOT IN (16)
			AND (p.EndOfSupportDate IS NULL OR p.EndOfSupportDate >= @FromDate)
			AND p.OfferSite IN (0, 2) -- Deposit
		
		DECLARE @ProductCodes VARCHAR(MAX)
		SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM @Products
	END

	-- Region: Get Party Settings
	BEGIN
		DECLARE @InvoiceData TABLE (IndexNumber INT IDENTITY(1, 1), InvoiceNumber INT, PartyId INT, InvoiceTypeId SMALLINT, InvoiceTypeShorten VARCHAR(10), IsHideRebateWorkSheet BIT)
		
		BEGIN TRY
			DECLARE @Party_XML XML = CONVERT(XML, @InvoiceGeneratingData)

			INSERT INTO @InvoiceData (InvoiceNumber, PartyId, InvoiceTypeShorten, InvoiceTypeId, IsHideRebateWorkSheet)
			SELECT InvoiceNumber, PartyId, InvoiceTypeShorten, CASE InvoiceTypeShorten WHEN 'S' THEN 1 WHEN 'R' THEN 3 WHEN 'H' THEN 6 END, CASE HideRebateWorksheet WHEN 'Y' THEN 1 ELSE 0 END
			FROM (
				SELECT
					t.c.value('(InvoiceNumber/text())[1]', 'INT') AS InvoiceNumber
					,t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
					,t.c.value('(InvoiceTypeShorten/text())[1]', 'VARCHAR(10)') AS InvoiceTypeShorten
					,t.c.value('(HideRebateWorkSheet/text())[1]', 'VARCHAR(10)') AS HideRebateWorkSheet
				FROM @Party_XML.nodes('Root/InvoiceGenerating') t(c)
			) a
			OPTION (OPTIMIZE FOR (@Party_XML = NULL))

			-- Remove duplicate data
			DELETE t
			FROM (
				SELECT PartyId, ROW_NUMBER() OVER(PARTITION BY PartyId, InvoiceTypeId ORDER BY InvoiceNumber) AS RN
				FROM @InvoiceData
			) t
			WHERE t.RN > 1
		END TRY
		BEGIN CATCH
			PRINT 'Wrong format XML'
		END CATCH

		DECLARE @PartySettings TABLE (PartyId INT, LicenseeId INT, PartyName VARCHAR(50), BrandName VARCHAR(100), BaseCurrencyId INT, BaseCurrencyName VARCHAR(10), InvoiceLanguage VARCHAR(50))
		INSERT INTO @PartySettings (PartyId, LicenseeId, PartyName, BrandName, BaseCurrencyId, BaseCurrencyName, InvoiceLanguage)
		SELECT p.PartyId, p.OldRefId, p.PartyName, ISNULL(NULLIF(pd.BrandName, ''), p.PartyName), ISNULL(bc.BaseCurrencyId, 6), ISNULL(CASE WHEN e.Code = 'UST' THEN 'USDT' ELSE e.Code END, 'EUR'), pd.InvoiceLanguage
		FROM (SELECT DISTINCT PartyId FROM @InvoiceData) i
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON p.PartyId = i.PartyId
			LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyId = p.PartyId
			LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
			LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON e.ExchangeId = bc.BaseCurrencyId

		DECLARE @InvoiceSymbol NVARCHAR(20)
		SELECT TOP 1 @InvoiceSymbol = InvoiceSymbol
		FROM dbo.LA_InvoiceHeader WITH (NOLOCK)
		WHERE StatusId <> -1 AND Environment = @Environment AND BillerId = @BillerId
			AND InvoiceType IN (1, 3, 6) -- Software Fee, Rebate, Hosting Fee
		ORDER BY CreatedDateTime DESC
		
		DECLARE @InvoiceSettings TABLE (IndexNumber INT, PartyId INT, BillerId INT, InvTypeId SMALLINT, ProductCodes VARCHAR(200), InvTemplateName VARCHAR(50), InvoiceSymbol NVARCHAR(20), InvoiceNumber INT, IsHideRebateWorkSheet BIT)
		INSERT INTO @InvoiceSettings (IndexNumber, PartyId, BillerId, InvTypeId, InvTemplateName, InvoiceSymbol, InvoiceNumber, ProductCodes, IsHideRebateWorkSheet)
		SELECT d.IndexNumber, s.FromPartyId, s.ToPartyId, s.InvTypeId, t.InvTemplateName, @InvoiceSymbol, d.InvoiceNumber
			, STUFF((SELECT ',' + CASE WHEN ls.ProductId = 0 THEN 'SB' ELSE ProductPrefix END
						FROM dbo.LA_InvoiceSetting ls WITH (NOLOCK)
							LEFT JOIN dbo.Product3rd p WITH (NOLOCK) ON ls.ProductId = p.ProductId
						WHERE s.InvTypeId = ls.InvTypeId AND s.FromPartyId = ls.FromPartyId AND s.ToPartyId = ls.ToPartyId
							AND ls.InvTypeId = 1 AND ls.ProductId IS NOT NULL
						FOR XML PATH('')), 1, 1, '') AS ProductCodes
			, d.IsHideRebateWorkSheet
		FROM @PartySettings ps
			INNER JOIN @InvoiceData d ON ps.PartyId = d.PartyId
			INNER JOIN dbo.LA_InvoiceSetting s WITH (NOLOCK) ON s.FromPartyId = ps.PartyId AND s.InvTypeId = d.InvoiceTypeId
			INNER JOIN dbo.LA_InvoiceTemplate t WITH (NOLOCK) ON s.InvTempId = t.InvTemplateId
		WHERE s.InvTypeId IN (1, 3, 6) AND s.ToPartyId = @BillerId
		GROUP BY d.IndexNumber, s.FromPartyId, s.ToPartyId, s.InvTypeId, t.InvTemplateName, d.InvoiceNumber, d.IsHideRebateWorkSheet

		-- Handle (Casino Promotion invoice setting)
		UPDATE @InvoiceSettings
		SET  ProductCodes = ProductCodes +',SPR(CS)'
		WHERE InvTypeId = 1 AND EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(ProductCodes,',') WHERE value <> 'SB')
	END
	-- End Region: Get Party Settings

	-- Region: Get Exchange
	BEGIN
		DECLARE @BaseCurrencies TABLE (RowId SMALLINT IDENTITY(1, 1), BaseCurrencyId INT, BaseCurrencyName VARCHAR(10))
		DECLARE @Exchange TABLE (ExchangeDate DATE, ExchangeId INT, CurrencyCode VARCHAR(65), BaseCurrencyId INT, BaseCurrencyRate FLOAT)
		
		INSERT INTO @BaseCurrencies (BaseCurrencyId, BaseCurrencyName)
		SELECT DISTINCT BaseCurrencyId, BaseCurrencyName FROM @PartySettings

		INSERT INTO @Exchange (ExchangeDate, ExchangeId, CurrencyCode, BaseCurrencyId, BaseCurrencyRate)
		SELECT e.ExchangeDate, e.ExchangeId, e.Code, bc.BaseCurrencyId, e.BaseCurrencyRate
		FROM @BaseCurrencies bc
			CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, bc.BaseCurrencyName) e
	END
	-- End Region: Get Exchange

	-- Region: Get hosting fee
	BEGIN
		DECLARE @HostingFee TABLE (PartyId INT, SettingType TINYINT, NoOfDate INT, Amount MONEY, CurrencyId INT)
		INSERT INTO @HostingFee (PartyId, SettingType, NoOfDate, Amount, CurrencyId)
		SELECT PartyId, SettingType, DATEDIFF(DAY, FromDate, ToDate) + 1, Amount, CurrencyId
		FROM (
			SELECT s.FromParty AS PartyId, s.SettingType, d.Amount, d.BaseCurrencyId AS CurrencyId
				,CASE WHEN s.FromDate < @FromDate THEN @FromDate ELSE s.FromDate END AS FromDate
				,CASE WHEN s.ToDate > @ToDate THEN @ToDate ELSE s.ToDate END AS ToDate
				,ROW_NUMBER() OVER(PARTITION BY s.FromParty, s.SettingType ORDER BY s.FromDate DESC) AS RN
			FROM dbo.LA_HostingFeesSetting s WITH (NOLOCK)
				LEFT JOIN dbo.LA_HostingFees f WITH (NOLOCK) ON s.HostingFeesId = f.HostingFeesId
				LEFT JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON f.HostingFeesId = d.HostingFeesId AND f.HostingFeesTypeId = 1 -- Fixed
			WHERE @FromDate <= s.ToDate AND @ToDate >= s.FromDate
		) s
		WHERE s.RN = 1 AND DATEDIFF(DAY, FromDate, ToDate) >= 0

		UPDATE h1
		SET h1.Amount = h1.Amount * ISNULL((1.0 * (h2.FeeDate - h2.WaiveDate) / h2.FeeDate), 1.0)
		FROM @HostingFee h1
			OUTER APPLY (
				SELECT TOP 1 h1.NoOfDate AS FeeDate, h2.NoOfDate AS WaiveDate
				FROM @HostingFee h2
				WHERE h1.PartyId = h2.PartyId AND h2.SettingType = 2
			) h2
		WHERE h1.SettingType = 1

		INSERT INTO @FinalResult (PartyId, BillerId, InvoiceType, LicensingFee)
		SELECT h.PartyId, ivs.BillerId, 6, h.Amount * e.BaseCurrencyRate
		FROM @HostingFee h
			INNER JOIN @PartySettings ps ON h.PartyId = ps.PartyId
			INNER JOIN @InvoiceSettings ivs ON h.PartyId = ivs.PartyId AND ivs.InvTypeId = 6 -- Hosting Fee
			INNER JOIN @Exchange e ON h.CurrencyId = e.ExchangeId AND ps.BaseCurrencyId = e.BaseCurrencyId AND e.ExchangeDate = @ToDate
		WHERE h.SettingType = 1
	END
	-- End Region: Get hosting fee

	-- Region: Get Licensing fee
	BEGIN
		DECLARE @temp_PartyIds VARCHAR(MAX), @temp_BaseCurrencyId INT, @temp_BaseCurrencyName VARCHAR(10), @RowId SMALLINT = 1

		DECLARE @Result TABLE
		(
			PartyId INT, ProductId INT, ProductCode VARCHAR(10), LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
			,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000),ExtraInfo NVARCHAR(4000)
		)
		
		WHILE 1 = 1
		BEGIN
			SELECT @Temp_PartyIds = NULL, @temp_BaseCurrencyId = NULL, @temp_BaseCurrencyName = NULL
			SELECT @temp_BaseCurrencyId = BaseCurrencyId, @temp_BaseCurrencyName = BaseCurrencyName FROM @BaseCurrencies WHERE RowId = @RowId
			SELECT @temp_PartyIds = COALESCE(@temp_PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM @PartySettings WHERE BaseCurrencyId = @temp_BaseCurrencyId

			IF @temp_PartyIds IS NULL
				BREAK

			INSERT INTO @Result
			(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
			)
			EXEC dbo.LA_AmountToCompanyByProduct
				@PartyIds = @temp_PartyIds
				,@ProductCodes = @ProductCodes
				,@FromDate = @FromDate
				,@ToDate = @ToDate
				,@IncludeTierRebate = 0
				,@LicensingFeeTypeIds = '0,-1,13' -- -1: Deduction (AMF, AGPrepayment, Prepayment, ...) 13: Deduct casino promotion
				,@BaseCurrencyName = @temp_BaseCurrencyName
				,@Environment = @Environment

			SET @RowId = @RowId + 1
		END

		UPDATE sb
		SET sb.ExtraAmount = sb.ExtraAmount - (ISNULL(p.LicensingFee,0) + ISNULL(p.ExtraAmount,0)) + ISNULL(p1.ExtraAmount,0) -- Saba Promotion Deducted, Add Tips
		FROM @Result sb
			LEFT JOIN @Result p ON sb.PartyId = p.PartyId AND p.ProductId = 37
			LEFT JOIN @Result p1 ON sb.PartyId = p1.PartyId AND p1.ProductId = 74
		WHERE sb.ProductId = 0 AND sb.LicensingFeeTypeId = 0

		DELETE @Result WHERE ProductId IN (37, 74)

		UPDATE r
		SET r.ProductCode = p.ProductPrefix
		FROM @Result r
			INNER JOIN dbo.LA_f_Products3rd('') p ON r.ProductId = p.ProductId

		UPDATE @Result SET ProductCode = 'SPR(CS)' WHERE ProductId = -37
		
		INSERT INTO @FinalResult (PartyId, BillerId, InvoiceType, ProductCodes, Discount, ExtraAmount, LicensingFee)
		SELECT t.PartyId, s.BillerId, 1, s.ProductCodes, SUM(ISNULL(t.Discount, 0)), SUM(t.ExtraAmount)
			,SUM(CASE WHEN t.LicensingFeeTypeId = 0 THEN ROUND(t.LicensingFee, 2) ELSE -t.LicensingFee END)
		FROM @Result t
			INNER JOIN @InvoiceSettings s ON t.PartyId = s.PartyId AND ',' + s.ProductCodes + ',' LIKE '%,' + t.ProductCode + ',%' AND s.InvTypeId = 1 -- Software Fee
		WHERE t.ProductId <> -37
		GROUP BY t.PartyId, s.BillerId, s.ProductCodes

		-- deduct casino promotion
		UPDATE f
		SET f.LicensingFee = f.LicensingFee - r.ExtraAmount
		FROM @FinalResult f
		INNER JOIN @Result r ON f.PartyId = r.PartyId AND r.LicensingFeeTypeId = 13
		WHERE f.InvoiceType = 1

		-- Prepayment
		UPDATE f
		SET f.LicensingFee = f.LicensingFee - CASE WHEN f.LicensingFee - f.Discount < r.LicensingFee THEN f.LicensingFee - f.Discount ELSE r.LicensingFee END
		FROM @FinalResult f
			INNER JOIN @Result r ON f.PartyId = r.PartyId AND r.ProductId = -99
		WHERE f.LicensingFee > 0 AND r.LicensingFee > 0

		INSERT INTO @FinalResult (PartyId, BillerId, InvoiceType, LicensingFee)
		SELECT t.PartyId, r.BillerId, 3, -SUM(ISNULL(t.Rebate, 0))
		FROM @Result t
			INNER JOIN @InvoiceSettings r ON t.PartyId = r.PartyId AND r.InvTypeId = 3 -- Rebate
		WHERE t.Rebate <> 0
		GROUP BY t.PartyId, r.BillerId

		DELETE @Result WHERE ProductId = - 37

		UPDATE @FinalResult SET LicensingFee = ISNULL(LicensingFee, 0) + ISNULL(ExtraAmount, 0) WHERE InvoiceType = 1 AND InvoiceHeaderId IS NULL
	END
	-- End Region: Get Licensing fee

	-- Region: Final Result
	BEGIN
		DECLARE @_Result TABLE
		(
			RowIndex INT, IndexNumber INT, PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(100), ItemType TINYINT, BillerId INT, BillerName NVARCHAR(50)
			,InvoiceHeaderId BIGINT, InvoiceSymbol NVARCHAR(20), InvoiceNumber INT, InvoicePath NVARCHAR(256)
			,BaseCurrencyId INT, BaseCurrencyName VARCHAR(10), InvoiceLanguage VARCHAR(50), ProductCodes VARCHAR(MAX)
			,LicensingFee MONEY, Discount MONEY, Rebate MONEY, AdjustmentAmount MONEY, AdjustmentNote NVARCHAR(500), IsHideRebateWorkSheet BIT
			,CompanyName NVARCHAR(100), BillerAddress1 NVARCHAR(255)
		)

		INSERT INTO @_Result
		(
			RowIndex, IndexNumber, PartyId, PartyName, BrandName, ItemType, BillerId, BillerName, InvoiceHeaderId, InvoiceSymbol, InvoiceNumber, InvoicePath
			,BaseCurrencyId, BaseCurrencyName, InvoiceLanguage, ProductCodes, LicensingFee, Discount, Rebate, AdjustmentAmount, AdjustmentNote, IsHideRebateWorkSheet
			,CompanyName, BillerAddress1
		)
		SELECT
			ROW_NUMBER() OVER(ORDER BY ISNULL(r.InvoiceNumber, ivs.InvoiceNumber)) AS RowIndex
			,ivs.IndexNumber
			,ps.PartyId
			,ps.PartyName
			,ps.BrandName
			,ivs.InvTypeId AS ItemType
			,ivs.BillerId
			,b.BillerName
			,r.InvoiceHeaderId
			,ivs.InvoiceSymbol
			,ISNULL(r.InvoiceNumber, ivs.InvoiceNumber) AS InvoiceNumber
			,r.InvoicePath
			,ps.BaseCurrencyId
			,ps.BaseCurrencyName
			,ps.InvoiceLanguage
			,CASE WHEN ivs.InvTypeId = 1 THEN ivs.ProductCodes ELSE '' END AS ProductCodes
			,SUM(ISNULL(CASE WHEN r.InvoiceType = 3 THEN 0 ELSE r.LicensingFee END, 0)) AS LicensingFee
			,-SUM(ISNULL(r.Discount, 0)) AS Discount
			,SUM(ISNULL(CASE WHEN r.InvoiceType = 3 THEN r.LicensingFee ELSE 0 END, 0)) AS Rebate
			,SUM(ISNULL(r.AdjustmentAmount, 0)) AS AdjustmentAmount
			,ISNULL(r.AdjustmentNote, N'') AS AdjustmentNote
			,ivs.IsHideRebateWorkSheet
			,b.CompanyName
			,b.Address1
		FROM @PartySettings ps
			INNER JOIN @InvoiceSettings ivs ON ps.PartyId = ivs.PartyId
			LEFT JOIN @FinalResult r ON ps.PartyId = r.PartyId AND ivs.BillerId = r.BillerId AND ivs.InvTypeId = r.InvoiceType
			INNER JOIN DBCUST.bodb_Licensee.dbo.LA_BillerInfo b WITH (NOLOCK) ON ivs.BillerId = b.PartyId
		GROUP BY
			ivs.IndexNumber
			,ps.PartyId
			,ps.PartyName
			,ps.BrandName
			,ivs.InvTypeId
			,ivs.BillerId
			,b.BillerName
			,r.InvoiceHeaderId
			,ivs.InvoiceSymbol
			,ISNULL(r.InvoiceNumber, ivs.InvoiceNumber)
			,r.InvoicePath
			,ps.BaseCurrencyId
			,ps.BaseCurrencyName
			,ps.InvoiceLanguage
			,CASE WHEN ivs.InvTypeId = 1 THEN ivs.ProductCodes ELSE '' END
			,ISNULL(r.AdjustmentNote, N'')
			,ivs.IsHideRebateWorkSheet
			,b.CompanyName
			,b.Address1
	END
	-- End Region: Final Result

	-- Return data
	SELECT RowIndex, IndexNumber, PartyId, PartyName, BrandName, ItemType, BillerId, BillerName, InvoiceHeaderId, InvoiceSymbol, InvoiceNumber, InvoicePath
		,BaseCurrencyId, BaseCurrencyName, InvoiceLanguage, ProductCodes, LicensingFee, Discount, Rebate, AdjustmentAmount, AdjustmentNote, IsHideRebateWorkSheet
		,CompanyName, BillerAddress1
	FROM @_Result
	ORDER BY InvoiceNumber
END
GO
