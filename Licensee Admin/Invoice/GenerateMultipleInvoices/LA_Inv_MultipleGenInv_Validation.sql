/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_Inv_MultipleGenInv_Validation]
	@BillerId				INT,
	@InvoiceGeneratingData	NVARCHAR(MAX),
	@FromDate				DATE,
	@ToDate					DATE,
	@Environment			VARCHAR(10)
AS

/*
	Created: 20210720@Percy
	DB: DBLIC.bodb_Licensee
	Task: Support a function to export all invoices at once: Generate Multiple Temporary Invoice - Validation
   
	Revisions: 
		- 20210720@Percy: Initialize SP [#147006]
		- 20220210@Percy: Support Tier Rebate [RedmineID: #163495]

	Param's Explanation:
		@InvoiceGeneratingData:
		'<Root>
			<InvoiceGenerating>
				<InvoiceNumber>123</InvoiceNumber>
				<PartyName>12BET</PartyName>
				<InvoiceTypeShorten>S</InvoiceTypeShorten>
			</InvoiceGenerating>
		</Root>'
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @PartyList TABLE (RowId INT, InvalidCellNumber VARCHAR(20) DEFAULT (''), InvoiceNumber VARCHAR(20), PartyId INT, PartyName VARCHAR(100), BaseCurrencyId INT, InvoiceTypeId SMALLINT, InvoiceTypeShorten VARCHAR(10), InvoiceTypeName VARCHAR(100), Error BIT DEFAULT(0), ContentValidation VARCHAR(2000) DEFAULT(''), SettingValidation VARCHAR(2000) DEFAULT(''))
	
	BEGIN TRY
		DECLARE @Party_XML XML = CONVERT(XML, @InvoiceGeneratingData)

		INSERT INTO @PartyList (RowId, InvoiceNumber, PartyName, InvoiceTypeShorten, InvoiceTypeId, InvoiceTypeName)
		SELECT 1000 * ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS RowId, InvoiceNumber, PartyName, InvoiceTypeShorten
			,CASE InvoiceTypeShorten WHEN 'S' THEN 1 WHEN 'R' THEN 3 WHEN 'H' THEN 6 END
			,CASE InvoiceTypeShorten WHEN 'S' THEN 'Software Data & Licensing Fees' WHEN 'R' THEN 'Rebate' WHEN 'H' THEN 'Hosting Fees' END
		FROM (
			SELECT
				LTRIM(RTRIM(t.c.value('(InvoiceNumber/text())[1]', 'VARCHAR(20)'))) AS InvoiceNumber
				,LTRIM(RTRIM(t.c.value('(PartyName/text())[1]', 'VARCHAR(100)'))) AS PartyName
				,LTRIM(RTRIM(t.c.value('(InvoiceTypeShorten/text())[1]', 'VARCHAR(10)'))) AS InvoiceTypeShorten
			FROM @Party_XML.nodes('Root/InvoiceGenerating') t(c)
		) a
		OPTION (OPTIMIZE FOR (@Party_XML = NULL))
	END TRY
	BEGIN CATCH
		PRINT 'Wrong format XML'
	END CATCH

	-- Check input data
	BEGIN
		-- Check invalid
		UPDATE p
		SET p.PartyId = op.PartyId
		FROM @PartyList p
			INNER JOIN dbo.OAS_Party op WITH (NOLOCK) ON p.PartyName = LTRIM(RTRIM(op.PartyName))
		WHERE op.PartyType IN (1, 5) -- licensees

		;WITH CTE_Data AS (
			SELECT p.RowId, t.CellNumber, CASE t.CellNumber WHEN 0 THEN 'invoice number' WHEN 1 THEN 'licensee name' WHEN 2 THEN 'invoice type' END AS ErrMsg
			FROM @PartyList p
				CROSS APPLY (
					SELECT 0 AS CellNumber, CASE WHEN ISNUMERIC(InvoiceNumber + '.e0') = 0 THEN 1 WHEN CONVERT(INT, InvoiceNumber) <= 0 THEN 1 ELSE 0 END AS ErrCode
					UNION ALL SELECT 1, CASE WHEN ISNULL(PartyName, '') = '' OR p.PartyId IS NULL THEN 1 ELSE 0 END
					UNION ALL SELECT 2, CASE WHEN ISNULL(InvoiceTypeId, 0) = 0 THEN 1 ELSE 0 END
				) t
			WHERE t.ErrCode <> 0
		)
		UPDATE p
		SET p.Error = 1
			,p.InvalidCellNumber = STUFF((SELECT ',' + CONVERT(VARCHAR(3), d.CellNumber) FROM CTE_Data d WHERE d.RowId = p.RowId FOR XML PATH('')), 1, 1, '')
			,p.ContentValidation = 'Invalid ' + STUFF((SELECT ', ' + d.ErrMsg FROM CTE_Data d WHERE d.RowId = p.RowId FOR XML PATH('')), 1, 2, '')
			,p.InvoiceTypeName = ISNULL(p.InvoiceTypeName, p.InvoiceTypeShorten)
		FROM @PartyList p
		WHERE EXISTS (SELECT 1 FROM CTE_Data d WHERE p.RowId = d.RowId)

		-- Check duplicate
		UPDATE p
		SET p.Error = 1, p.ContentValidation = c.ContentValidation, p.RowId = c.RN
		FROM @PartyList p
			INNER JOIN (
				SELECT CASE WHEN d.PartyId IS NOT NULL AND n.InvoiceNumber IS NOT NULL THEN 'Duplicated invoice number, licensee name, invoice type'
															WHEN d.PartyId IS NOT NULL THEN 'Duplicated licensee name, invoice type' ELSE 'Duplicated invoice number' END AS ContentValidation
					,p.RowId
					,ISNULL(d.RowId, n.RowId) + ROW_NUMBER() OVER(ORDER BY ISNULL(d.PartyId, 0) DESC, ISNULL(n.InvoiceNumber, '') DESC, p.RowId) AS RN
				FROM @PartyList p
					LEFT JOIN (
						SELECT PartyId, InvoiceTypeId, MIN(RowId) AS RowId
						FROM @PartyList
						WHERE Error = 0
						GROUP BY PartyId, InvoiceTypeId
						HAVING COUNT(1) > 1
					) d ON p.PartyId = d.PartyId AND p.InvoiceTypeId = d.InvoiceTypeId
					LEFT JOIN (
						SELECT InvoiceNumber, MIN(RowId) AS RowId
						FROM @PartyList
						WHERE Error = 0
						GROUP BY InvoiceNumber
						HAVING COUNT(1) > 1
					) n ON p.InvoiceNumber = n.InvoiceNumber
				WHERE p.Error = 0 AND (d.PartyId IS NOT NULL OR n.InvoiceNumber IS NOT NULL)
			) c ON p.RowId = c.RowId
	END

	-- Update Party Info
	DECLARE @PartyBaseCurrency TABLE (PartyId INT, BaseCurrencyId INT)
	INSERT INTO @PartyBaseCurrency (PartyId, BaseCurrencyId)
	SELECT DISTINCT PartyId, BaseCurrencyId
	FROM dbo.OAS_PartyBaseCurrency WITH (NOLOCK)
	WHERE FromDate <= @ToDate AND ToDate >= @FromDate

	UPDATE p
	SET p.BaseCurrencyId = bc.BaseCurrencyId
		,p.Error = CASE WHEN bc.PartyId IS NULL OR ISNULL(bc.BaseCurrencyId, 0) = 0 THEN 1 ELSE 0 END
		,p.ContentValidation = CASE WHEN bc.PartyId IS NULL OR ISNULL(bc.BaseCurrencyId, 0) = 0 THEN 'Missing setting base currency' ELSE '' END
	FROM @PartyList p
		LEFT JOIN @PartyBaseCurrency bc ON p.PartyId = bc.PartyId
	WHERE p.Error = 0

	-- Check Invoice Number is in use
	UPDATE p
	SET p.Error = 1, p.SettingValidation = 'Invoice number is in use'
	FROM @PartyList p
	WHERE EXISTS (
		SELECT 1 FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
		WHERE h.BillerId = @BillerId
			AND h.Environment = @Environment
			AND ISNULL(h.StatusId, 0) <> -1 -- 0: normal, -1: void, 1: closed
			AND h.InvoiceNumber = p.InvoiceNumber
	)
		AND p.Error = 0

	-- Check Party belong to Biller
	DECLARE @InvoiceSettings TABLE (PartyId INT, InvoiceTypeId SMALLINT)
	INSERT INTO @InvoiceSettings (PartyId, InvoiceTypeId)
	SELECT DISTINCT s.FromPartyId, s.InvTypeId
	FROM dbo.LA_InvoiceSetting s WITH (NOLOCK)
		INNER JOIN dbo.LA_InvoiceTemplate t WITH (NOLOCK) ON s.InvTempId = t.InvTemplateId
	WHERE s.ToPartyId = @BillerId

	UPDATE p
	SET p.Error = 1
		,p.SettingValidation = 'Do not belong to selected biller'
	FROM @PartyList p
		LEFT JOIN @InvoiceSettings s ON p.PartyId = s.PartyId AND p.InvoiceTypeId = s.InvoiceTypeId
	WHERE p.Error = 0 AND s.PartyId IS NULL

	-- Check Party Setting
	BEGIN
		-- For Discount & Rebate
		DECLARE @Discount TABLE (PartyId INT, BaseCurrencyId INT, DiscountType TINYINT)
		INSERT INTO @Discount (PartyId, BaseCurrencyId, DiscountType)
		SELECT DISTINCT a.PartyId, h.CurrencyId, CASE WHEN h.DiscountGroupType NOT IN (2, 12) THEN 1 ELSE 2 END -- 1: discount, 2: rebate
		FROM dbo.LA_DiscountGroupHeader h WITH (NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH (NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
		WHERE h.FromDate <= @ToDate AND h.ToDate >= @FromDate

		-- Charge Rate & Rebate
		UPDATE p
		SET p.Error = CASE	WHEN c.PartyId IS NULL THEN 1 -- missing charge rate
							WHEN d.PartyId IS NULL AND p.InvoiceTypeId = 3 THEN 1 -- missing rebate
							ELSE 0 END
			,p.ContentValidation = CASE	WHEN c.PartyId IS NULL THEN 'Invalid charge rate' -- missing charge rate
										WHEN d.PartyId IS NULL AND p.InvoiceTypeId = 3 THEN 'Invalid rebate rate' -- missing rebate
										ELSE '' END
									+ CASE WHEN c.PartyId IS NULL AND d.PartyId IS NULL AND p.InvoiceTypeId = 3 THEN ', rebate rate' ELSE '' END
		FROM @PartyList p
			LEFT JOIN (
				SELECT DISTINCT FromParty AS PartyId
				FROM dbo.OAS_ChargeInfo WITH (NOLOCK)
				WHERE FromDate <= @ToDate AND ToDate >= @FromDate
					AND ToParty IN (1, 9, 11, 98)
					AND ChargeType NOT IN (2, 3) -- old type, no use
			) c ON p.PartyId = c.PartyId
			LEFT JOIN @Discount d ON p.PartyId = d.PartyId AND p.InvoiceTypeId = 3 AND d.DiscountType = 2 -- Rebate
		WHERE p.Error = 0 AND p.InvoiceTypeId IN (1, 3) -- Software Fee & Rebate
			AND (c.PartyId IS NULL OR d.PartyId IS NULL)

		-- Hosting Fee
		DECLARE @HostingFee TABLE (PartyId INT, BaseCurrencyId INT)
		INSERT INTO @HostingFee (PartyId, BaseCurrencyId)
		SELECT DISTINCT s.FromParty, f.BaseCurrencyId
		FROM dbo.LA_HostingFeesSetting s WITH (NOLOCK)
			INNER JOIN dbo.LA_HostingFees f WITH (NOLOCK) ON s.HostingFeesId = f.HostingFeesId
			INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON f.HostingFeesId = d.HostingFeesId AND f.HostingFeesTypeId = 1
		WHERE s.FromDate <= @ToDate AND s.ToDate >= @FromDate

		UPDATE p
		SET p.Error = 1, p.ContentValidation = 'Invalid hosting fees rate'
		FROM @PartyList p
			LEFT JOIN @HostingFee h ON p.PartyId = h.PartyId
		WHERE p.Error = 0 AND p.InvoiceTypeId = 6 -- Hosting Fee
			AND h.PartyId IS NULL
	END

	-- Check Base Currency
	BEGIN
		-- For Min Fee / Group Min Fee
		DECLARE @MinFee TABLE (PartyId INT, BaseCurrencyId INT, IsGroup BIT)
		INSERT INTO @MinFee (PartyId, BaseCurrencyId, IsGroup)
		SELECT DISTINCT a.PartyId, d.CurrencyId, 1
		FROM dbo.LA_GroupMinFeeHeader h WITH (NOLOCK)
			INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH (NOLOCK) ON h.GroupMinFeeId = a.GroupMinFeeId
			INNER JOIN dbo.LA_GroupMinFeeDetail d WITH (NOLOCK) ON h.GroupMinFeeId = d.GroupMinFeeId
		WHERE h.FromDate <= @ToDate AND h.ToDate >= @FromDate

		INSERT INTO @MinFee (PartyId, BaseCurrencyId, IsGroup)
		SELECT m.PartyId, m.CurrencyId, 0
		FROM (
			SELECT DISTINCT PartyId, CurrencyId
			FROM dbo.LA_MinFee WITH (NOLOCK)
			WHERE FromDate <= @ToDate AND ToDate >= @FromDate
				AND FeeTypeId = 1 -- Exclude waive min fee
		) m
			LEFT JOIN @MinFee t ON m.PartyId = t.PartyId
		WHERE t.PartyId IS NULL

		-- Check Base Currency of Discount /Min Fee /Group Min Fee
		UPDATE p
		SET p.Error = 1, p.SettingValidation = 'Mismatch setting base currency: '
												+ CASE WHEN d.PartyId IS NOT NULL THEN 'Discount' ELSE '' END
												+ CASE WHEN m.PartyId IS NULL THEN '' ELSE CASE WHEN d.PartyId IS NOT NULL THEN ', ' ELSE '' END + CASE WHEN m.IsGroup = 0 THEN 'MinFee' ELSE 'Group Min Fee' END END
		FROM @PartyList p
			LEFT JOIN @Discount d ON p.PartyId = d.PartyId AND p.BaseCurrencyId <> d.BaseCurrencyId AND d.DiscountType = 1 -- discount
			LEFT JOIN @MinFee m ON p.PartyId = m.PartyId AND p.BaseCurrencyId <> m.BaseCurrencyId
		WHERE p.Error = 0 AND p.InvoiceTypeId IN (1, 3) -- Software Fee & Rebate
			AND d.PartyId IS NOT NULL OR m.PartyId IS NOT NULL

		-- Check Base Currency of Hosting Fee
		UPDATE p
		SET p.Error = 1, p.SettingValidation = 'Mismatch setting base currency: Hosting Fees'
		FROM @PartyList p
			INNER JOIN @HostingFee h ON p.PartyId = h.PartyId AND p.BaseCurrencyId <> h.BaseCurrencyId
		WHERE p.Error = 0 AND p.InvoiceTypeId = 6 -- Hosting Fee
	END

	-- Return data
	SELECT InvalidCellNumber, InvoiceNumber, PartyId, PartyName, InvoiceTypeId, InvoiceTypeShorten, InvoiceTypeName, ContentValidation, SettingValidation
	FROM @PartyList
	ORDER BY RowId
END
GO