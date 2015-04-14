USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingModify] 
	@BillerID				INT				
	, @PayerID				INT				= 0
	, @InvoiceSettingXML	VARCHAR (5000)
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150414@Florent
	 Task : Create new Biller
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
	 Params:
		+ @InvoiceSettingXML: '<InvoiceSettings>
									<InvoiceSetting>
										<InvoiceTypeId>1</InvoiceTypeId>  
										<InvoiceTemplateId>1</InvoiceTemplateId>
										<ProductIds ProductId = "1"></ProductIds>
										<ProductIds ProductId = "3"></ProductIds>
										<ProductIds ProductId = "5"></ProductIds>
									</InvoiceSetting>
							
									<InvoiceSetting>
										<InvoiceTypeId>2</InvoiceTypeId>  
										<InvoiceTemplateId>1</InvoiceTemplateId>
										<ProductIds />
									</InvoiceSetting>
							
									<InvoiceSetting>
										<InvoiceTypeId>3</InvoiceTypeId>  
										<InvoiceTemplateId>3</InvoiceTemplateId>
										<ProductIds />
									</InvoiceSetting>
								</InvoiceSettings>'
*/
SET NOCOUNT ON
BEGIN
	IF ISNULL( @PayerID, '') = ''
		RETURN
-- For writing log
	DECLARE 
		@startRun		DATETIME,
		@endRun			DATETIME,
		@duration		INT,
		@logSPData		VARCHAR(5000),
		@logSPDataOld	VARCHAR(5000),
		@xml			XML

	-- Time start
	SET @startRun = GETDATE()
	-- parse XML
	DECLARE @InvoiceSetting AS TABLE (InvoiceTypeId INT, InvoiceTemplateId INT, ProductId INT)
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @InvoiceSettingXML

	INSERT INTO @InvoiceSetting( InvoiceTypeId, InvoiceTemplateId, ProductId)
	SELECT InvoiceTypeId, InvoiceTemplateId, ProductId
	FROM OPENXML(@idoc, 'InvoiceSettings/InvoiceSetting/ProductIds')
	WITH (
		InvoiceTypeId VARCHAR(10) '../InvoiceTypeId',
		InvoiceTemplateId VARCHAR(10) '../InvoiceTemplateId',
		ProductId VARCHAR(10) '@ProductId'
	)
	-- Case Insert New setting
	IF NOT EXISTS (SELECT 1 
					FROM dbo.LA_InvoiceSetting i WITH (NOLOCK) 
						INNER JOIN @InvoiceSetting t ON i.ProductId = t.ProductId
					WHERE i.FromPartyId = @PayerID AND i.ToPartyId = @BillerID)
	BEGIN
		INSERT INTO dbo.LA_InvoiceSetting(FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId)
		SELECT @PayerId, @BillerID, ProductId, InvoiceTypeId, InvoiceTemplateId
		FROM @InvoiceSetting

		IF @@error <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Insert failed. Please try again.', @ErrCode = 1	
			RETURN
		END

		--write log
		SET @xml = (
				SELECT	@PayerId				AS '@f'
						, @BillerID				AS '@t'
						, ProductId				AS '@p'
						, InvoiceTypeId			AS '@itp'
						, InvoiceTemplateId		AS '@itm'					
				FROM @InvoiceSetting
				FOR XML PATH('z'), ROOT('r')			
				)
			SET @logSpData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

			SET @endRun = GETDATE()
			SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 	

	END
	-- Case Update
	ELSE
	BEGIN		
		SET @xml = (
				SELECT	FromPartyId		AS '@f'
						, ToPartyId		AS '@t'
						, ProductId		AS '@p'
						, InvTypeId		AS '@itp'
						, InvTempId		AS '@itm'					
				FROM dbo.LA_InvoiceSetting WITH (NOLOCK)
				WHERE FromPartyId = @PayerID
					AND ToPartyId = @BillerID
				FOR XML PATH('z'), ROOT('r')			
				)
		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')

		DELETE FROM dbo.LA_InvoiceSetting WITH (ROWLOCK, UPDLOCK)				
			WHERE FromPartyId = @PayerID 
				AND ToPartyId = @BillerId
				AND EXISTS (SELECT 1 FROM dbo.LA_InvoiceSetting i WITH (NOLOCK) INNER JOIN @InvoiceSetting t ON i.ProductId = t.ProductId
					WHERE i.FromPartyId = @PayerID AND i.ToPartyId = @BillerID)

		INSERT INTO dbo.LA_InvoiceSetting(FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId)
		SELECT @PayerId, @BillerID, ProductId, InvoiceTypeId, InvoiceTemplateId
		FROM @InvoiceSetting 

		IF @@error <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Insert failed. Please try again.', @ErrCode = 1	
			RETURN
		END

		--write log		
		SET @xml = (
				SELECT	@PayerId				AS '@f'
						, @BillerID				AS '@t'
						, ProductId				AS '@p'
						, InvoiceTypeId			AS '@itp'
						, InvoiceTemplateId		AS '@itm'					
				FROM @InvoiceSetting
				FOR XML PATH('z'), ROOT('r')			
				)
			SET @logSpData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	

			SET @endRun = GETDATE()
			SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
	END

	--Write Log		
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_InvoiceSettingModify'

	EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
		@UserId = @UserID
		, @IP = @LoginIP
		, @LicenseeID = 0
		, @CurrencyID = 0
		, @SPName = 'LA_InvoiceSettingModify'
		, @CustId = 0
		, @ActionId = @ActionID
		, @Duration = @duration
		, @Data = @logSPData
		, @OldData = @logSPDataOld
	
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_InvoiceSettingModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_InvoiceSettingModify] TO bodbAdminNet 