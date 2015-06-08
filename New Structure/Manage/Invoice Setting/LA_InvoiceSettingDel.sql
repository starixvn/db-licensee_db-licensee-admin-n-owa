USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
	 Params:	
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

	--Write Log		
	DECLARE @ActionID INT = 0
	SELECT ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_InvoiceSettingDel'
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_InvoiceSettingDel'
			, @CustId = 0
			, @ActionId = @ActionID
			, @Duration = @duration
			, @Data = @logSPData
			, @OldData = @logSPDataOld
	END TRY
	BEGIN CATCH
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP 
			@UserID = @UserID
			, @CustID = 0
			, @ActionID = @ActionID
			, @TrackingValue = @LogSPData
			, @TrackingValue2 = @logSPDataOld
			, @duration = @duration
	END CATCH	
	
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_InvoiceSettingDel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_InvoiceSettingDel] TO bodbAdminNet 