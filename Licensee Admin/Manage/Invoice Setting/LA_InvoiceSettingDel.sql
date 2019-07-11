/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingDel] 
	@BillerID				INT				
	, @PayerID				INT					
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150414@Florent
	 Task : Biller Delete Payer setting
	 DB: DBCUST.bodb_Licensee
   
	 Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]

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
BEGIN
	SET NOCOUNT ON
	IF ISNULL(@PayerID, '') = '' OR ISNULL(@BillerID, '') = ''
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
	
	IF EXISTS (SELECT 1 
					FROM dbo.LA_InvoiceSetting i WITH (NOLOCK) 						
					WHERE i.FromPartyId = @PayerID AND i.ToPartyId = @BillerID)	
	BEGIN		
		SET @xml = (
				SELECT	FromPartyId		AS '@f'
						, ToPartyId		AS '@t'
						, ProductId		AS '@p'
						, InvTypeId		AS '@itp'
						, InvTempId		AS '@itm'		
						, BankId		AS '@b'			
				FROM dbo.LA_InvoiceSetting WITH (NOLOCK)
				WHERE FromPartyId = @PayerID
					AND ToPartyId = @BillerID
				FOR XML PATH('z'), ROOT('r')			
				)
		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')

		--delete statement
		DELETE FROM dbo.LA_InvoiceSetting WITH (ROWLOCK, UPDLOCK)				
			WHERE FromPartyId = @PayerID 
				AND ToPartyId = @BillerId

		IF @@error <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 140	
			RETURN
		END

		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
	END

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_InvoiceSettingDel'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO