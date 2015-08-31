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
	, @MinfeeInsertedList	NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 2015042$@Florent
	 Task : Add/ Modify Minfee setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:			
		- 20150618@Florent: add column Currency to LA_Minfee   	
		- 20150831@Bravo: fix bug - Min fee term & Basis of billing max length.
	 Params:		
		+ @InvoiceSettingXML: '<MinFeeSettings>
								<MinFeeSetting>
									<MinFeeId>1</MinFeeId>
									<ProductId>1</ProductId>		
									<FeeAmount>1</FeeAmount>
									<CurrencyId>1</CurrencyId>
									<FeeTypeId>1</FeeTypeId>
									<MinFeeTerm>1</MinFeeTerm>									
									<FromDate>1</FromDate>
									<ToDate>1</ToDate>
									<IsEdit>1</IsEdit>
								</MinFeeSetting>	
								<MinFeeSetting>
									<MinFeeId>2</MinFeeId>
									<ProductId>1</ProductId>		
									<FeeAmount>1</FeeAmount>
									<CurrencyId>1</CurrencyId>
									<FeeTypeId>1</FeeTypeId>
									<MinFeeTerm>1</MinFeeTerm>									
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
	IF ISNULL(@MinFeeSettingXML, '') = ''
		RETURN
	-- parse XML
	DECLARE @MinFeeSetting AS TABLE (Idx INT IDENTITY(1,1), MinFeeId INT,ProductId INT, FeeAmount MONEY, CurrencyId INT, FeeTypeId INT, MinFeeTerm VARCHAR(MAX), Priority SMALLINT, FromDate DATE, ToDate DATE, IsEdit BIT)	
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @MinFeeSettingXML
	
	BEGIN TRY
		INSERT INTO @MinFeeSetting(MinFeeId, ProductId, FeeAmount, CurrencyId, FeeTypeId, MinFeeTerm, Priority, FromDate, ToDate, IsEdit)
		SELECT MinFeeId
			, ProductId
			, FeeAmount
			, CurrencyId
			, FeeTypeId
			, MinFeeTerm
			, CASE WHEN FeeTypeId = 1 -- Minfee			
					THEN 1
					ELSE 2 -- other: Waive fee
				END AS Priority
			, FromDate
			, ToDate
			, IsEdit
		FROM OPENXML(@idoc, 'MinFeeSettings/MinFeeSetting')
		WITH (				
			 MinFeeId		INT				'MinFeeId'
			, ProductId		INT				'ProductId'		
			, FeeAmount		MONEY			'FeeAmount'
			, CurrencyId	INT				'CurrencyId'
			, FeeTypeId		INT				'FeeTypeId'
			, MinFeeTerm	VARCHAR(MAX)	'MinFeeTerm'		
			, FromDate		DATE			'FromDate'
			, ToDate		DATE			'ToDate'
			, IsEdit		BIT				'IsEdit' 
		)
	END TRY
	BEGIN CATCH
		SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 802	
		RETURN
	END CATCH

	EXEC sp_xml_removedocument @idoc
		
	--IF NOT EXISTS ( SELECT TOP 1 1 FROM @MinFeeSetting)
	--BEGIN 
	--	SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 801
	--	RETURN
	--END	
	-- check overlap time charge
	INSERT INTO @MinFeeSetting(MinFeeId, ProductId, FeeAmount, CurrencyId, FeeTypeId, MinFeeTerm, Priority, FromDate, ToDate)
	SELECT MinFeeId, ProductId, FeeAmount, CurrencyId, FeeTypeId, MinFeeTerm, Priority, FromDate, ToDate
	FROM dbo.LA_MinFee m WITH (NOLOCK)
	WHERE PartyId = @PayerID
		AND EXISTS( SELECT 1 FROM @MinFeeSetting WHERE m.FeeTypeId = FeeTypeId)
		AND	NOT EXISTS (SELECT ISNULL(MinFeeId, 0) FROM @MinFeeSetting mf WHERE m.MinFeeId = mf.MinFeeId)		
	
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
		DECLARE @ActionID INT = 0
		SELECT @ActionID = ActionId
		FROM bodb_CustomerLog.dbo.LogAction_Lic WITH (NOLOCK)
		WHERE SPName = 'LA_MinFeeSettingModify'

		-- case Update
		IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting cs WHERE IsEdit = 1)
			BEGIN
				-- write log
				--build log string
				SET @xml = (
						SELECT	cs.MinFeeId				AS '@m'
								, mf.PartyId			AS '@p'  
								, mf.ProductId			AS '@pr'								
								, mf.FeeAmount			AS '@fa'
								, mf.CurrencyId			AS '@c'
								, mf.MinFeeTerm			AS '@mft'								
								, mf.FromDate			AS '@fd'
								, mf.ToDate				AS '@td'
								, mf.Priority			AS '@pri'
						FROM @MinFeeSetting  cs
							INNER JOIN dbo.LA_MinFee mf WITH (NOLOCK) ON cs.FeeTypeId = mf.FeeTypeId AND cs.MinFeeId = mf.MinFeeId AND mf.PartyId = @PayerID AND cs.IsEdit = 1
						FOR XML PATH('z'), ROOT('r')			
						)
				SET @logSPDataOld = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');
				
				;MERGE dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK) AS t
				USING (SELECT MinFeeId, FeeTypeId, ProductId, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, Priority FROM @MinFeeSetting WHERE IsEdit = 1) AS s
				ON (t.MinFeeId = s.MinFeeId)
				WHEN MATCHED
					THEN UPDATE SET t.FeeAmount = s.FeeAmount	
								, t.CurrencyId = s.CurrencyId															
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
						SELECT	mf.MinFeeId				AS '@m'
								, mf.PartyId			AS '@p'  								
								, mf.ProductId			AS '@pr'
								, mf.FeeAmount			AS '@fa'
								, mf.CurrencyId			AS '@c'
								, mf.MinFeeTerm			AS '@mft'								
								, mf.FromDate			AS '@fd'
								, mf.ToDate				AS '@td'
								, mf.Priority			AS '@pri'
						FROM @MinFeeSetting  cs
							INNER JOIN dbo.LA_MinFee mf WITH (NOLOCK) ON cs.FeeTypeId = mf.FeeTypeId AND cs.MinFeeId = mf.MinFeeId AND mf.PartyId = @PayerID AND cs.IsEdit = 1
						FOR XML PATH('z'), ROOT('r')			
						)
				SET @logSPData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');
				SET @endRun = GETDATE()
				SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

				--Write Log
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
		IF EXISTS (SELECT TOP 1 1 FROM @MinFeeSetting cs WHERE IsEdit = 0)			
		BEGIN 
			DECLARE @MinFeeID AS TABLE (MinFeeID INT)

			INSERT INTO dbo.LA_MinFee WITH (ROWLOCK, UPDLOCK)(PartyId, FeeTypeId, ProductID, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, Priority)	
			OUTPUT INSERTED.MinFeeId
			INTO @MinFeeID	
			SELECT @PayerId, FeeTypeId, ProductID, FeeAmount, CurrencyId, FromDate, ToDate, MinFeeTerm, Priority
			FROM @MinFeeSetting
			WHERE ISNULL(MinFeeId, 0) = 0
				
			SELECT @MinfeeInsertedList = COALESCE(@MinfeeInsertedList + ',' + CAST(MinFeeId AS VARCHAR), CAST(MinFeeId AS VARCHAR))
			FROM @MinFeeID
										
			IF @@ERROR <> 0
			BEGIN
				SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 802	
				RETURN
			END							
					
			SET @xml = (
					SELECT	cs.MinFeeId				AS '@m'
							, m.PartyId				AS '@p'  
							, m.ProductId			AS '@pr'								
							, m.FeeAmount			AS '@fb'
							, m.CurrencyId			AS '@c'
							, m.MinFeeTerm			AS '@bb'								
							, m.FromDate			AS '@fd'
							, m.ToDate				AS '@td'
							, m.Priority			AS '@pri'
					FROM @MinFeeID cs
						INNER JOIN dbo.LA_MinFee m WITH (NOLOCK) ON cs.MinFeeID = m.MinFeeId						
					FOR XML PATH('z'), ROOT('r')			
					)
			SET @logSPData = REPLACE(CONVERT(VARCHAR(MAX), @xml), '" />', '"/"');
			SET @endRun = GETDATE()
			SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 
			SET @logSPDataOld = NULL

			--Write Log
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
	END
	ELSE
	BEGIN		
		--raise error
		SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date'
			, @ErrCode = 800
		RETURN		
	END	
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_MinFeeSettingModify] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_MinFeeSettingModify] TO bodbAdminNet