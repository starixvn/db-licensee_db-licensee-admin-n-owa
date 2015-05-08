USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_MinFeeSettingModify] 	
	@PayerID				INT	
	, @MinFeeSettingXML		VARCHAR (5000)
	, @ExchangeID			INT
	, @UserID				INT
	, @LoginIP				VARCHAR (50)	= ''
	, @ErrCode				INT				= 0		OUTPUT
	, @ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
	, @ErrorPair			NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 2015042$@Florent
	 Task : Add/ Modify Minfee setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     
	 Params:		
		+ @InvoiceSettingXML: '<MinFeeSettings>
								<MinFeeSetting>
									<Index>1</Index>
									<MinFeeId>1</MinFeeId>
									<ProductId>1</ProductId>		
									<FeeAmount>1</FeeAmount>
									<FeeTypeId>1</FeeTypeId>
									<MinFeeTerm>1</MinFeeTerm>
									<Priority>1</Priority>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
									<IsEdit>1</IsEdit>
								</MinFeeSetting>	
								<MinFeeSetting>
									<Index>2</Index>
									<MinFeeId>2</MinFeeId>
									<ProductId>1</ProductId>		
									<FeeAmount>1</FeeAmount>
									<FeeTypeId>1</FeeTypeId>
									<MinFeeTerm>1</MinFeeTerm>
									<Priority>1</Priority>
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
									<IsEdit>1</IsEdit>
								</MinFeeSetting>
								</MinFeeSettings>'
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData VARCHAR(5000), @logSPDataOld VARCHAR(5000),	@xml XML
	DECLARE @ProductListAll		VARCHAR(100) = ''
			, @MinDate			DATE 
			, @MaxDate			DATE
	SET @startRun = GETDATE()
	
	-- parse XML
	DECLARE @MinFeeSetting AS TABLE (Idx INT IDENTITY(1,1), MinFeeId INT,ProductId INT, FeeAmount MONEY, FeeTypeId INT, MinFeeTerm VARCHAR(100), Priority SMALLINT, FromDate DATE, ToDate DATE, IsEdit BIT)	
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @MinFeeSettingXML

	INSERT INTO @MinFeeSetting(MinFeeId, ProductId, FeeAmount, FeeTypeId, MinFeeTerm, Priority, FromDate, ToDate, IsEdit)
	SELECT MinFeeId, ProductId, FeeAmount, FeeTypeId, MinFeeTerm, Priority, FromDate, ToDate, IsEdit
	FROM OPENXML(@idoc, 'MinFeeSettings/MinFeeSetting')
	WITH (				
		 MinFeeId		INT				'MinFeeId'
		, ProductId		INT				'ProductId'		
		, FeeAmount		MONEY			'FeeAmount'
		, FeeTypeId		INT				'MinFeeType'
		, MinFeeTerm	VARCHAR			'MinFeeTerm'
		, Priority		SMALLINT		'Priority'
		, FromDate		DATE			'FromDate'
		, ToDate		DATE			'ToDate'
		, IsEdit		BIT				'IsEdit' 
	)
	--WHERE FeeTypeId = 1
	EXEC sp_xml_removedocument @idoc
		
	IF NOT EXISTS ( SELECT TOP 1 1 FROM @MinFeeSetting)
	BEGIN 
		SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 801
		RETURN
	END	

	-- check overlap time charge
	INSERT INTO @MinFeeSetting(MinFeeId, ProductId, FeeTypeId, FromDate, ToDate)
	SELECT MinFeeId, ProductId, FeeTypeId, FromDate, ToDate 
	FROM dbo.LA_MinFee m WITH (NOLOCK)
	WHERE PartyId = @PayerID
		AND EXISTS( SELECT 1 FROM @MinFeeSetting WHERE m.FeeTypeId = FeeTypeId)
		AND	NOT EXISTS (SELECT MinFeeId FROM @MinFeeSetting mf WHERE m.MinFeeId = mf.MinFeeId)		
	SELECT * FROM @MinFeeSetting
	---check case Update , compare new data with old config 
	IF NOT EXISTS (
			SELECT TOP 1 1
			FROM @MinFeeSetting a LEFT JOIN @MinFeeSetting b ON a.Idx != b.Idx AND a.ProductId = b.ProductId AND a.FeeTypeId = b.FeeTypeId
			WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
						OR a.ToDate BETWEEN b.FromDate AND b.ToDate
						OR b.FromDate BETWEEN a.FromDate AND a.ToDate
						OR b.ToDate BETWEEN a.FromDate AND a.ToDate
					))
	BEGIN
		-- case Update
			IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting cs WHERE IsEdit = 1)
			BEGIN
				-- write log
				--build log string
				SET @xml = (
						SELECT	mf.MinFeeId				AS '@m'
								, mf.PartyId			AS '@p'  
								, cs.ProductId			AS '@pr'								
								, mf.FeeAmount			AS '@fa'
								, mf.MinFeeTerm			AS '@mft'								
								, mf.FromDate			AS '@fd'
								, mf.ToDate				AS '@td'
								, mf.Priority			AS '@pri'
						FROM @MinFeeSetting  cs
							INNER JOIN dbo.LA_MinFee mf WITH (NOLOCK) ON cs.FeeTypeId = mf.FeeTypeId
						FOR XML PATH('z'), ROOT('r')			
						)
				SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');
				SELECT * FROM @MinFeeSetting
				
				;MERGE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) AS t
				USING (SELECT MinFeeId, FeeTypeId, ProductId, FeeAmount, FromDate, ToDate, MinFeeTerm, Priority FROM @MinFeeSetting WHERE IsEdit = 1) AS s
				ON (t.MinFeeId = s.MinFeeId)
				WHEN MATCHED
					THEN UPDATE SET t.FeeAmount = s.FeeAmount																
								, t.FromDate = s.FromDate
								, t.ToDate = s.ToDate
								, t.ProductId = s.ProductId
								, t.MinFeeTerm = s.MinFeeTerm;			
				
				IF @@ERROR <> 0
				BEGIN
					SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 802	
					RETURN
				END
					
				SET @xml = (
						SELECT	cs.MinFeeId				AS '@m'
								, mf.PartyId			AS '@p'  								
								, cs.ProductId			AS '@pr'
								, cs.FeeAmount			AS '@fb'
								, cs.MinFeeTerm			AS '@bb'								
								, cs.FromDate			AS '@fd'
								, cs.ToDate				AS '@td'
								, cs.Priority			AS '@pri'
						FROM @MinFeeSetting  cs
							INNER JOIN dbo.LA_MinFee mf WITH (NOLOCK) ON cs.FeeTypeId = mf.FeeTypeId
						FOR XML PATH('z'), ROOT('r')			
						)
				SET @logSPData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');
				SET @endRun = GETDATE()
				SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
			END
			IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting cs WHERE IsEdit = 0)			
			BEGIN 
				INSERT INTO dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)(PartyId, FeeTypeId, ProductID, FeeAmount, FromDate, ToDate, MinFeeTerm, Priority)				
				SELECT @PayerId, FeeTypeId, ProductID, FeeAmount, FromDate, ToDate, MinFeeTerm, Priority
				FROM @MinFeeSetting
				WHERE MinFeeId = 0
											
				IF @@ERROR <> 0
				BEGIN
					SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 802	
					RETURN
				END							
					
				SET @xml = (
						SELECT	cs.MinFeeId				AS '@m'
								, @PayerID				AS '@p'  
								, cs.ProductId			AS '@pr'								
								, cs.FeeAmount			AS '@fb'
								, cs.MinFeeTerm			AS '@bb'								
								, cs.FromDate			AS '@fd'
								, cs.ToDate				AS '@td'
								, cs.Priority			AS '@pri'
						FROM @MinFeeSetting  cs							
						FOR XML PATH('z'), ROOT('r')			
						)
				SET @logSPData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');
				SET @endRun = GETDATE()
				SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
			END
	END
	ELSE
	BEGIN
		SELECT @ErrorPair = COALESCE(@ErrorPair + ',' + '( ' +CAST(a.MinFeeId AS VARCHAR)+','+ CAST(b.MinFeeId AS VARCHAR) +' )', '( ' +CAST(a.MinFeeId AS VARCHAR)+', '+ CAST(b.MinFeeId AS VARCHAR) +' )')
		FROM @MinFeeSetting a LEFT JOIN @MinFeeSetting b ON a.Idx != b.Idx AND a.ProductId = b.ProductId AND a.FeeTypeId = b.FeeTypeId
			WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
						OR a.ToDate BETWEEN b.FromDate AND b.ToDate
						OR b.FromDate BETWEEN a.FromDate AND a.ToDate
						OR b.ToDate BETWEEN a.FromDate AND a.ToDate)
		SET @ErrorPair = SUBSTRING(@ErrorPair, 0, LEN(@ErrorPair)/2 +1)
		--raise error
		SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date'
			, @ErrCode = 800
		RETURN		
	END
	--Write Log		
	DECLARE @ActionID INT = 0
	SELECT @ActionID = ActionId
	FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
	WHERE SPName = 'LA_MinFeeSettingModify'
	
	BEGIN TRY
		EXEC bodb_CustomerLog.dbo.NAP_SpecialCustSetting_WriteLog 
			@UserId = @UserID
			, @IP = @LoginIP
			, @LicenseeID = 0
			, @CurrencyID = 0
			, @SPName = 'LA_MinFeeSettingModify'
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
GRANT VIEW DEFINITION ON [dbo].[LA_MinFeeSettingModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_MinFeeSettingModify] TO bodbAdminNet