/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Statement_PaymentAllocationIns]
	@PartyID		INT,
	@Environment	VARCHAR(10)		= 'LOCAL',
	@AllocationData	NVARCHAR(MAX),
	@ErrCode		INT				= 0 OUTPUT,
	@ErrMsg			NVARCHAR(200)	= '' OUTPUT,
	@UserID         INT,
	@LoginIP        VARCHAR(45)

AS

/*
	Created: 20231122@Danny
	DB: DBCUST.bodb_Licensee
	Task:  payment allocation 
   
	Revisions: 
		- 20230908@Danny: Initialize SP [#194603]

	Param's Explanation:

	@AllocationData = 
		'<Root>
			<Item>
				<LicenseeCode>PHL-LSEE-12BET EUR</LicenseeCode>
				<SettlementType>Invoice Settlement</SettlementType>
				<DocumentID>10173</DocumentID>
				<InvoiceAmount></InvoiceAmount>
				<PaymentAmount>120.00</PaymentAmount>
				<AppliedAmount>-120.00</AppliedAmount>
			</Item>
			<Item>
				<LicenseeCode>PHL-LSEE-12BET EUR</LicenseeCode>
				<SettlementType>Invoice Settlement</SettlementType>
				<DocumentID>20083</DocumentID>
				<InvoiceAmount>-100</InvoiceAmount>
				<PaymentAmount></PaymentAmount>
				<AppliedAmount>-50.00</AppliedAmount>
			</Item>
			<Item>
				<LicenseeCode>PHL-LSEE-12BET EUR</LicenseeCode>
				<SettlementType>Invoice Settlement</SettlementType>
				<DocumentID>20115</DocumentID>
				<InvoiceAmount>6400.45</InvoiceAmount>
				<PaymentAmount></PaymentAmount>
				<AppliedAmount>170.00</AppliedAmount>
			</Item>
		</Root>'

*/

BEGIN
	SET NOCOUNT ON

	DECLARE @AllocationItemList TABLE (
		RowNumber				INT ,
		LicenseeCode			VARCHAR(50), 
		SettlementType			VARCHAR(50), 
		DocumentID				INT, 
		DocumentNo				VARCHAR(50), 
		InvoiceAmount			MONEY, 
		PaymentAmount			MONEY, 
		AppliedAmount			MONEY,
		CurrentRemainingAmt		MONEY,
		DocumentTypeID			TINYINT,  -- 0: Inv, 1: Payment
		DocumentDetailTypeID	INT,	  -- InvTypeID, PaymentTypeID
		RemainingAmt			MONEY,
		IsConvertSignAmt		BIT,
		DocumentDate			DATETIME,
		DocumentType			VARCHAR(200)
		)

	DECLARE @IsMixsettlement BIT = 0, 
			@logSPData		NVARCHAR(MAX),
			@logSPDataOld	NVARCHAR(MAX),
			@actionID		INT = 2201,
			@startRun		DATETIME,
			@endRun			DATETIME,
			@duration		INT,
			@LicenseeCode	VARCHAR(50)

	-- Time start
	SET @startRun = GETDATE()
	
	BEGIN TRY
		DECLARE @Allocation_XML XML = CONVERT(XML, @AllocationData)

		INSERT INTO @AllocationItemList (LicenseeCode, SettlementType, DocumentID, InvoiceAmount, PaymentAmount, AppliedAmount,DocumentTypeID, IsConvertSignAmt)
		SELECT  LicenseeCode, 
				SettlementType, 
				DocumentID, 
				InvoiceAmount, 
				PaymentAmount, 
				AppliedAmount, 
				CASE WHEN CAST(InvoiceAmount AS MONEY) <> 0 THEN 0 ELSE 1 END DocumentTypeID,
				0 AS IsConvertSignAmt
		FROM (
			SELECT
				LTRIM(RTRIM(t.c.value('(LicenseeCode/text())[1]', 'VARCHAR(50)'))) AS LicenseeCode
				,LTRIM(RTRIM(t.c.value('(SettlementType/text())[1]', 'VARCHAR(50)'))) AS SettlementType
				,LTRIM(RTRIM(t.c.value('(DocumentID/text())[1]', 'INT'))) AS DocumentID
				,LTRIM(RTRIM(t.c.value('(InvoiceAmount/text())[1]', 'MONEY'))) AS InvoiceAmount
				,LTRIM(RTRIM(t.c.value('(PaymentAmount/text())[1]', 'MONEY'))) AS PaymentAmount
				,LTRIM(RTRIM(t.c.value('(AppliedAmount/text())[1]', 'MONEY'))) AS AppliedAmount
			FROM @Allocation_XML.nodes('Root/Item') t(c)
		) a
		OPTION (OPTIMIZE FOR (@Allocation_XML = NULL))

	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 100,  @ErrMsg = 'Wrong format XML.'
	END CATCH

	IF NOT EXISTS (SELECT 1 FROM @AllocationItemList)
	BEGIN
		SELECT @ErrCode = 105,  @ErrMsg = 'No selected documents.'
		RETURN
	END

	-- Validation input
	IF EXISTS (SELECT TOP 1 1 FROM @AllocationItemList GROUP BY LicenseeCode HAVING SUM(AppliedAmount) <> 0)
	BEGIN
		SELECT @ErrCode = 101,  @ErrMsg = 'All allocation must be "all positive amount" = "all negative amount".'
		RETURN
	END

	-- Get current Remaining Amount of Documents
	BEGIN
		-- Invoice
		UPDATE t
		SET t.CurrentRemainingAmt = ISNULL(i.RemainingAmount, i.Amount),
			t.DocumentDetailTypeID = i.InvoiceType,
			t.IsConvertSignAmt = 0,
			t.DocumentDate = i.InvoiceDate,
			t.DocumentNo = i.OfficialInvoiceNo,
			t.DocumentType = li.InvTypeName + ISNULL(d.InvoiceList,''),
			t.RemainingAmt = ISNULL(i.RemainingAmount, i.Amount) -- Use to allocate
		FROM @AllocationItemList t
		INNER JOIN LA_InvoiceHeader i WITH(NOLOCK) ON t.DocumentID = i.InvoiceHeaderId AND i.PartyId = @PartyID
		INNER JOIN LA_InvoiceType li WITH(NOLOCK) ON i.InvoiceType = li.InvTypeId
		OUTER APPLY (
			SELECT  ' for ' +  STRING_AGG(x.OfficialInvoiceNo,', ') AS InvoiceList
			FROM
			(
				SELECT DISTINCT d.OfficialInvoiceNo  OfficialInvoiceNo
				FROM  LA_InvoiceStatement st WITH(NOLOCK) 
				INNER JOIN LA_InvoiceHeader d WITH(NOLOCK) ON st.RefNo = d.OfficialInvoiceNo AND d.InvoiceType IN (1,3,6,7) AND d.StatusId <> -1
				WHERE  t.DocumentID = st.InvoiceHeaderId AND i.InvoiceType IN (4,5)
			)x
		) d
		WHERE DocumentTypeID = 0

		-- Payment
		UPDATE t
		SET t.CurrentRemainingAmt = i.RemainingAmount,
			t.DocumentDetailTypeID = i.Type,
			t.DocumentDate = i.ReceivedDate,
			t.DocumentNo = i.PaymentNo,
			t.DocumentType = i.Remark,
			t.RemainingAmt = i.RemainingAmount -- Use to allocate
		FROM @AllocationItemList t
		INNER JOIN LA_Payment i WITH(NOLOCK) ON t.DocumentID = i.PaymentId  AND i.PartyId = @PartyID
		WHERE DocumentTypeID = 1


		; WITH t AS 
		(
			SELECT DocumentID, DocumentTypeID, ROW_NUMBER() OVER (ORDER BY DocumentDate) AS RowNumber FROM @AllocationItemList
		)UPDATE l
		SET l.RowNumber = t.RowNumber
		FROM @AllocationItemList l
		INNER JOIN t ON l.DocumentID = t.DocumentID AND l.DocumentTypeID = t.DocumentTypeID

	END

	IF EXISTS (	SELECT	TOP 1 1 
				FROM	@AllocationItemList 
				WHERE ( CurrentRemainingAmt <> InvoiceAmount AND DocumentTypeID = 0)
					OR (CurrentRemainingAmt <> PaymentAmount AND DocumentTypeID = 1)
				)
	BEGIN
		SELECT @ErrCode = 102,  @ErrMsg = 'Remaining amount has changed, the data need to be refreshed before.'
		RETURN
	END

	IF EXISTS (SELECT 1  FROM @AllocationItemList WHERE SettlementType = 'Invoice Settlement' ) 
		AND EXISTS (SELECT 1  FROM @AllocationItemList WHERE SettlementType = 'Rebate Settlement' ) 
		SELECT @IsMixsettlement = 1

	IF @IsMixsettlement = 1 
	BEGIN
		DECLARE @IsAllowMixSettlementAllocate BIT = 0 

		-- Mix settlement allocation is just allowed in some special cases.
		; WITH allowed AS -- Document is allowed allocate mix settlement   
		(
			SELECT SettlementType, DocumentTypeID, DocumentDetailTypeID, AppliedAmount, DocumentID
			FROM @AllocationItemList t 
			WHERE (DocumentTypeID = 0 AND DocumentDetailTypeID IN (1,5,6) AND AppliedAmount > 0 AND SettlementType = 'Invoice Settlement')
			OR (DocumentTypeID = 0 AND DocumentDetailTypeID IN (3) AND AppliedAmount < 0 AND SettlementType = 'Rebate Settlement')
		)
		SELECT  @IsAllowMixSettlementAllocate = 1
		WHERE NOT EXISTS ( SELECT TOP 1 1 
						FROM @AllocationItemList   t 
						LEFT JOIN allowed u ON u.SettlementType = t.SettlementType
								AND u.DocumentTypeID = t.DocumentTypeID
								AND u.DocumentDetailTypeID = t.DocumentDetailTypeID
								AND u.DocumentID = t.DocumentID 
						WHERE u.DocumentID IS NULL
						)
		IF @IsAllowMixSettlementAllocate = 0
		BEGIN
			SELECT @ErrCode = 103,  @ErrMsg = 'Invoice settlement and rebate settlement cannot be settled within a transaction, please check.'
			RETURN
		END

	END

	SELECT TOP 1 @LicenseeCode =  LicenseeCode FROM @AllocationItemList

	SELECT @logSPData = (
		SELECT	   Op.PartyName	AS 'gi.p'
					,@LicenseeCode		AS 'gi.lc'
					,inv.inv AS 'is'
					,rebate.rb AS 'rs'
		FROM OAS_Party op WITH(NOLOCK)
		OUTER APPLY 
		(
			SELECT (
				SELECT FORMAT(DocumentDate,'MMM dd, yyyy') AS 'd', 
					   DocumentNo AS 'dn',
					   DocumentType AS 'dt',
					   FORMAT(InvoiceAmount,'N','en-us') AS 'ia',
					   FORMAT(PaymentAmount,'N','en-us') AS 'pa',
					   FORMAT(AppliedAmount,'N','en-us') AS 'am',
					   CAST(DocumentTypeID AS VARCHAR(2)) + CAST(DocumentID AS VARCHAR(50)) AS FakeID
				FROM @AllocationItemList inv
				WHERE inv.SettlementType  = 'Invoice Settlement' 
				FOR JSON PATH ) AS inv
		) inv
		OUTER APPLY 
		(
			SELECT (
				SELECT FORMAT(DocumentDate,'MMM dd, yyyy') AS 'd1', 
					   DocumentNo AS 'dn1',
					   DocumentType AS 'dt1',
					   FORMAT(InvoiceAmount,'N','en-us') AS 'ia1',
					   FORMAT(PaymentAmount,'N','en-us') AS 'pa1',
					   FORMAT(AppliedAmount,'N','en-us') AS 'am1',
					   CAST(DocumentTypeID AS VARCHAR(2)) + CAST(DocumentID AS VARCHAR(50)) AS FakeID
				FROM @AllocationItemList inv
				WHERE inv.SettlementType  = 'Rebate Settlement' 
				FOR JSON PATH ) AS rb
		) rebate
		WHERE op.PartyID = @PartyID
		FOR JSON PATH , WITHOUT_ARRAY_WRAPPER , INCLUDE_NULL_VALUES    
	)

	-- Allocate
	BEGIN
		-- Calculate allocation statement
		DECLARE @Allocation TABLE (
			ID						INT IDENTITY (1,1),
			FromDocumentId			BIGINT,
			FromDocumentTypeID		TINYINT,
			FromBeforeAppliedAmount	MONEY,
			FromAppliedAmount		MONEY,
			FromAfterAppliedAmount	MONEY,
			ToDocumentId			BIGINT,
			ToDocumentTypeID		TINYINT,
			ToBeforeAppliedAmount	MONEY,
			ToAppliedAmount			MONEY,
			ToAfterAppliedAmount	MONEY
		)

		DECLARE @cnt INT = 1, @id INT

		WHILE EXISTS (SELECT 1 FROM @AllocationItemList WHERE AppliedAmount <> 0)
		BEGIN
			; WITH t AS 
			(
				SELECT
					   t.DocumentID		AS FromDocumentId,
					   t.DocumentTypeID AS FromDocumentTypeID,
					   t.RemainingAmt FromBeforeAppliedAmount,
					   CASE WHEN t.DocumentTypeID = 0 AND t.IsConvertSignAmt = 0 THEN 1 ELSE -1 END * CASE WHEN ABS(t.AppliedAmount) >= ABS(u.AppliedAmount) THEN SIGN(t.AppliedAmount) * ABS(u.AppliedAmount) ELSE t.AppliedAmount END  AS FromAppliedAmount,
					   t.RemainingAmt 
					   -  CASE WHEN t.DocumentTypeID = 0 AND t.IsConvertSignAmt = 0 THEN 1 ELSE -1 END * CASE WHEN ABS(t.AppliedAmount) >= ABS(u.AppliedAmount) THEN SIGN(t.AppliedAmount) * ABS(u.AppliedAmount) ELSE t.AppliedAmount END  as FromAfterAppliedAmount, 

					   u.DocumentID as ToDocumentId,
					   u.DocumentTypeID as ToDocumentTypeID, 
					   u.RemainingAmt ToBeforeAppliedAmount,
					   CASE WHEN u.DocumentTypeID = 0 AND t.IsConvertSignAmt = 0 THEN 1 ELSE -1 END * CASE WHEN ABS(t.AppliedAmount) >= ABS(u.AppliedAmount) THEN u.AppliedAmount ELSE SIGN(u.AppliedAmount) * ABS(t.AppliedAmount) END  AS ToAppliedAmount,
					   u.RemainingAmt
					   - CASE WHEN u.DocumentTypeID = 0 AND t.IsConvertSignAmt = 0 THEN 1 ELSE -1 END *  CASE WHEN ABS(t.AppliedAmount) >= ABS(u.AppliedAmount) THEN u.AppliedAmount ELSE SIGN(u.AppliedAmount) * ABS(t.AppliedAmount) END as ToAfterAppliedAmount

				FROM  (SELECT TOP 1 * FROM  @AllocationItemList t WHERE t.AppliedAmount <> 0 ORDER BY t.RowNumber ) t
				CROSS APPLY (
					SELECT TOP 1 u.DocumentID, u.DocumentTypeID, u.DocumentDetailTypeID ,u.InvoiceAmount, u.AppliedAmount , u.PaymentAmount, u.IsConvertSignAmt, u.RemainingAmt
					FROM @AllocationItemList u 
					WHERE u.RowNumber > t.RowNumber AND SIGN(u.AppliedAmount) <> SIGN(t.AppliedAmount) AND u.AppliedAmount <> 0
					ORDER BY u.RowNumber
				) u
			)
			INSERT INTO @Allocation (
				FromDocumentId			,
				FromDocumentTypeID		,
				FromBeforeAppliedAmount	,
				FromAppliedAmount		,
				FromAfterAppliedAmount	,
				ToDocumentId			,
				ToDocumentTypeID		,
				ToBeforeAppliedAmount	,
				ToAppliedAmount			,
				ToAfterAppliedAmount	
			)
			SELECT FromDocumentId		,
				FromDocumentTypeID		,
				FromBeforeAppliedAmount	,
				FromAppliedAmount		,
				FromAfterAppliedAmount	,
				ToDocumentId			,
				ToDocumentTypeID		,
				ToBeforeAppliedAmount	,
				ToAppliedAmount			,
				ToAfterAppliedAmount	 
			FROM t

			SELECT  @cnt = @@ROWCOUNT, @id = SCOPE_IDENTITY()

			IF @cnt > 0
			BEGIN
				UPDATE t
				SET  t.RemainingAmt = u.RemainingAmt,
					 t.AppliedAmount = u.AppliedAmount
				FROM @AllocationItemList t
				CROSS APPLY (
					SELECT 
						  CASE WHEN t.DocumentID = u.FromDocumentId THEN u.FromAfterAppliedAmount ELSE u.ToAfterAppliedAmount END RemainingAmt,
						  t.AppliedAmount 
						  - CASE WHEN t.DocumentTypeID = 0  AND t.IsConvertSignAmt = 0 THEN 1 ELSE -1 END 
						  *  CASE WHEN t.DocumentID = u.FromDocumentId THEN FromAppliedAmount ELSE ToAppliedAmount END AppliedAmount
					FROM  @Allocation u 
					WHERE (t.DocumentID = u.FromDocumentId OR t.DocumentID = u.ToDocumentId) AND u.ID = @id
					
				) u
			END
		END
	END

	-- Insert allocation step and update remaining amount of document
	UPDATE t
	SET  t.RemainingAmount = u.RemainingAmt,
	     t.StatusId = CASE WHEN u.RemainingAmt = 0 THEN 1 ELSE t.StatusId END,-- Close
		 t.UpdatedBy = @UserID,
		 t.UpdatedDateTime = GETDATE()

	FROM LA_InvoiceHeader t WITH(ROWLOCK)
	INNER JOIN @AllocationItemList u ON t.InvoiceHeaderId = u.DocumentID AND u.DocumentTypeID = 0 AND t.Environment = @Environment

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Could not allocate due to an error has occurred.', @ErrCode = 104
		RETURN
	END

	UPDATE t
	SET  t.RemainingAmount = u.RemainingAmt,
	      t.StatusId = CASE WHEN u.RemainingAmt = 0 THEN 1 ELSE t.StatusId END, -- Close
		  t.ModifiedBy = @UserID,
		  t.ModifyDate = GETDATE()
	FROM LA_Payment t WITH(ROWLOCK)
	INNER JOIN @AllocationItemList u ON t.PaymentId = u.DocumentID AND u.DocumentTypeID = 1 AND t.Environment = @Environment

	IF @@ERROR <> 0
	BEGIN
		-- Rollback Invoice
		UPDATE t
		SET  t.RemainingAmount = u.CurrentRemainingAmt,
			 t.StatusId = 0
		FROM LA_InvoiceHeader t WITH(ROWLOCK)
		INNER JOIN @AllocationItemList u ON t.InvoiceHeaderId = u.DocumentID AND u.DocumentTypeID = 0 AND t.Environment = @Environment

		SELECT @ErrMsg = 'Could not allocate due to an error has occurred.', @ErrCode = 104
		RETURN
	END

	INSERT INTO LA_Allocation (
		PartyID					,
		FromDocumentId			,
		FromDocumentTypeID		,
		FromBeforeAppliedAmount	,
		FromAppliedAmount		,
		FromAfterAppliedAmount	,
		ToDocumentId			,
		ToDocumentTypeID		,
		ToBeforeAppliedAmount	,
		ToAppliedAmount			,
		ToAfterAppliedAmount	,
		CreatedDate				,
		CreatedBy				,
		UpdatedDate				,
		UpdatedBy				,
		Environment
	)
	SELECT 
		@PartyID				,
		FromDocumentId			,
		FromDocumentTypeID		,
		FromBeforeAppliedAmount	,
		FromAppliedAmount		,
		FromAfterAppliedAmount	,
		ToDocumentId			,
		ToDocumentTypeID		,
		ToBeforeAppliedAmount	,
		ToAppliedAmount			,
		ToAfterAppliedAmount	,
		GETDATE()				,
		@UserID					,
		GETDATE()				,
		@UserID					,
		@Environment
	FROM @Allocation

	IF @@ERROR <> 0
	BEGIN
		-- Rollback Invoice
		UPDATE t
		SET  t.RemainingAmount = u.CurrentRemainingAmt,
			 t.StatusId = 0
		FROM LA_InvoiceHeader t WITH(ROWLOCK)
		INNER JOIN @AllocationItemList u ON t.InvoiceHeaderId = u.DocumentID AND u.DocumentTypeID = 0 AND t.Environment = @Environment
		
		-- Rollback Payment
		UPDATE t
		SET  t.RemainingAmount = u.CurrentRemainingAmt,
			 t.StatusId = 0
		FROM LA_Payment t WITH(ROWLOCK)
		INNER JOIN @AllocationItemList u ON t.PaymentId = u.DocumentID AND u.DocumentTypeID = 1 AND t.Environment = @Environment
			
		SELECT @ErrMsg = 'Could not allocate due to an error has occurred.', @ErrCode = 104
		RETURN
	END

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			 = @UserID
		,@IP			 = @LoginIP
		,@SPName		 = 'LA_Statement_PaymentAllocationIns'
		,@CustId		 = @PartyID
		,@Duration		 = @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue  = @LogSPDataOld
		,@ActionID		 = @actionID


END
GO
