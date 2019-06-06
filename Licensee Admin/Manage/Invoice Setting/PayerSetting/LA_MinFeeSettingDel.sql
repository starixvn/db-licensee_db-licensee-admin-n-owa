/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_Licensee
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
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:     
		- 20150618@Florent: add column Currency to LA_Minfee  
		- 20150918@Victor: Support Chinese on Settings
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
	 
	 Params:				
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX),	@xml XML	
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
		SET @logSPDataOld = REPLACE(CONVERT(NVARCHAR(MAX), @xml), '" />', '"/"')	
		
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
	
	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_MinFeeSettingDel'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO