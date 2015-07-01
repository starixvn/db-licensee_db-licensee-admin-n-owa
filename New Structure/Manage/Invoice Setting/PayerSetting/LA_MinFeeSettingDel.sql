USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_MinFeeSettingDel] 	
	@MinfeeId				INT	
	, @PayerId				INT
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150504@Florent
	 Task : Delete Minfee setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
		- 20150618@Florent: add column Currency to LA_Minfee  
	 Params:				
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData VARCHAR(5000), @logSPDataOld VARCHAR(5000),	@xml XML	
	SET @startRun = GETDATE()
	
	IF ISNULL(@MinfeeId, 0 ) = 0 OR ISNULL(@PayerId, 0) = 0
		RETURN
	
	DECLARE @Minfee AS TABLE (MinfeeID INT, PartyId INT, FeeType INT, ProductId INT, FromDate DATE, ToDate DATE)	
	
	INSERT INTO @Minfee(MinfeeID, PartyId, FeeType, ProductId, FromDate, ToDate)
	SELECT MinFeeId, PartyId, FeeTypeId, ProductId, FromDate, ToDate 
	FROM dbo.LA_MinFee WITH (NOLOCK) 
	WHERE MinFeeId = @MinfeeId

	--check validate existing 
	EXEC dbo.LA_MinFeeValidate 
		@MinfeeId = @MinfeeId
		, @PayerIdList = @PayerID
		, @Mode = 'R'
		, @ErrCode = @ErrCode OUTPUT
		, @ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0 
	BEGIN		
		RETURN
	END
	---check case Update , compare new data with old config 
	IF EXISTS (SELECT 1 FROM @Minfee)
	BEGIN	
		SET @xml = (
				SELECT	m.MinFeeId				AS '@m'
						, m.PartyId				AS '@p'
						, m.FeeTypeId			AS '@ft'
						, m.ProductId			AS '@pr'
						, m.FeeAmount			AS '@fa'						
						, m.CurrencyId			AS '@c'						
						, m.FromDate			AS '@fd'
						, m.ToDate				AS '@td'
						, m.MinFeeTerm			AS '@mft'
						, m.Priority			AS '@pri'						
				FROM @Minfee mf
					INNER JOIN dbo.LA_MinFee m WITH (NOLOCK) ON mf.MinfeeID = m.MinFeeId
				FOR XML PATH('z'), ROOT('r')			
				)
		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	
		
		DELETE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)
		WHERE MinFeeId = @MinfeeId AND PartyId = @PayerID

		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 820	
			RETURN
		END
			
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
			
	END
	ELSE
	BEGIN		
		SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 820	
		RETURN		
	END
	--Write Log		
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_MinFeeSettingDel'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_MinFeeSettingDel'
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
GRANT VIEW DEFINITION ON [dbo].[LA_MinFeeSettingDel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_MinFeeSettingDel] TO bodbAdminNet