USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateSettingDel] 	
	@ChargeId				INT	
	, @PayerId				INT
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
	, @ErrorPair			NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20150427@Florent
	 Task : Delete Charge rate setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
	 Params:				
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData VARCHAR(5000), @logSPDataOld VARCHAR(5000),	@xml XML
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	SET @startRun = GETDATE()
	
	IF ISNULL(@ChargeId, 0 ) = 0 OR ISNULL(@PayerId, 0) = 0
		RETURN
	
	DECLARE @ChargeRate AS TABLE (ChargeID INT, PartyId INT, ProductId INT, FromDate DATE, ToDate DATE)	
	--get list Product
	SELECT @ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM dbo.LA_f_Products3rd('')
	SET @ProductListAll = REPLACE(SUBSTRING(@ProductListAll, 0, LEN(@ProductListAll)), 'RB', '')

	--get Minium date, maximum date
	SELECT @MinDate = MIN(ci.FromDate)
		, @MaxDate = MAX(ci.ToDate)
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2

	INSERT INTO @ChargeRate(ChargeID, PartyId, ProductId, FromDate, ToDate)
	SELECT ChargeID, PartyId, ProductId, FromDate, ToDate 
	FROM dbo.LA_f_ChargeInfo(@PayerID, @MinDate, @MaxDate ,@ProductListAll, 'OA', 1)		

	--check validate existing 
	EXEC dbo.LA_ChargeRateValidate 
		@ChargeId = @ChargeId
		, @PayerIdList = @PayerID
		, @Mode = 'R'
		, @ErrCode = @ErrCode OUTPUT
		, @ErrMsg = @ErrMsg OUTPUT
	IF @ErrCode <> 0 
	BEGIN
		RETURN
	END
	---check case Update , compare new data with old config 
	IF EXISTS (SELECT 1 FROM @ChargeRate)
	BEGIN	
		SET @xml = (
				SELECT	ci.ChargeId				AS '@c'
						, ci.ProductId			AS '@pr'
						, ci.FromParty			AS '@fp'
						, ci.ToParty			AS '@tp'
						, ci.ParentChargeID		AS '@pc'
						, ci.Rate				AS '@r'
						, ci.ChargeType			AS '@ct'
						, ci.FromDate			AS '@fd'
						, ci.ToDate				AS '@td'
						, ci.MinAmount			AS '@mi'
						, ci.MaxAmount			AS '@ma'
						, ci.Remark				AS '@re'
						, ci.BaseCurrencyId		AS '@cu'			
						, ci.FirstOfBilling		AS '@fb'
						, ci.BasicOfBilling		AS '@bb'
				FROM @ChargeRate cs
					INNER JOIN dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON cs.ChargeID = ci.ChargeID
				FOR XML PATH('z'), ROOT('r')			
				)
		SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"')	
		
		DELETE dbo.OAS_ChargeInfo WITH (ROWLOCK, UPDLOCK)
		WHERE ChargeID = @ChargeId AND FromParty = @PayerId

		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 710	
			RETURN
		END

		DELETE dbo.LA_ChargeInfo_SystemMapping WITH (ROWLOCK, UPDLOCK)
		WHERE ChargeID = @ChargeId
			AND SystemID = 2
											
		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 710	
			RETURN
		END				
			
		SET @endRun = GETDATE()
		SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
			
	END
	ELSE
	BEGIN		
		SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 710	
		RETURN		
	END
	--Write Log		
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_ChargeRateSettingDel'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_ChargeRateSettingDel'
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
GRANT VIEW DEFINITION ON [dbo].[LA_ChargeRateSettingDel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_ChargeRateSettingDel] TO bodbAdminNet