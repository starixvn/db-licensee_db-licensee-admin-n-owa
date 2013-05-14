set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go

ALTER  PROCEDURE [dbo].[OA_LicenseeProductAddNew]
	@LicenseeID INT,
	@ProductID INT,
	@isComm BIT=0,
	@isWL	BIT=0,
	@EffectiveDate SMALLDATETIME,
	@modifyDate SMALLDATETIME,
	@usrID INT ,
	@IP	  VARCHAR(30),		
	@ErrCode int = 0 OUTPUT , 
	@ErrMsg nvarchar(1000) = '' OUTPUT 
AS
/*  
 * Created: 20130116@Jim
 * Task :  Licensee Product & feature management
 * DB: DB052.bodb02  
 *  
 * Revisions:     
 
 * Parameter explanation
	
*/
SET NOCOUNT ON

DECLARE @startRun DATETIME
DECLARE @endRun DATETIME
DECLARE @duration INT
DECLARE @LogSPData VARCHAR(5000)
SET @startRun = GETDATE()

BEGIN	
	DELETE bodb_licensee.dbo.LicenseeProduct3rd
	WHERE LicenseeID=@LicenseeID
		AND ProductID=@ProductID
		
	INSERT INTO bodb_licensee.dbo.LicenseeProduct3rd (LicenseeID,ProductID,Comm,Winloss,EffectiveDate)
		SELECT 
			@LicenseeID
			,@ProductID
			,@isComm Comm
			,@isWL Winloss
			,@EffectiveDate  EffectiveDate
		IF @ProductID=2 -- Number Game
			BEGIN 
					DELETE  bodb_licensee.dbo.LicenseeFunctions
					WHERE LicenseeID=@LicenseeID AND FunctionID=23
					
					INSERT INTO bodb_licensee.dbo.LicenseeFunctions(LicenseeID,FunctionID)
					SELECT @licenseeID,23 -- Number Game
					
					DELETE  bodb_licensee.dbo.LicenseeUserFunctions
					WHERE 	LicenseeID=@LicenseeID AND FunctionID=23
					
					INSERT INTO bodb_licensee.dbo.LicenseeUserFunctions(UserID,FunctionID,LicenseeId)
					SELECT UserID,23,@LicenseeID -- totalbet/number game
					FROM bodb_licensee.dbo.LicenseeUserFunctions WITH (NOLOCK)
					WHERE LicenseeID=@LicenseeID AND FunctionID=1 -- total bet
						
			END 
		IF @ProductID=1 -- Horse Racing,Live Casino, Virtual Sport 
			BEGIN 
				
					INSERT INTO bodb_licensee.dbo.LicenseeFunctions(LicenseeID,FunctionID)
					SELECT @licenseeID,34 -- Racing Commission
					UNION 
					SELECT @licenseeID,35 -- Daily Racing Win Loss
					UNION
					SELECT @licenseeID,22 -- Racing
					
					INSERT INTO bodb_licensee.dbo.LicenseeUserFunctions(UserID,FunctionID,LicenseeId)
					SELECT UserID,34 ,@LicenseeID -- Racing Commission
					FROM bodb_licensee.dbo.LicenseeUserFunctions WITH (NOLOCK)
					WHERE LicenseeID=@LicenseeID AND FunctionID =27 --- Licensee WinLoss Report 
					UNION 
					SELECT UserID,35 ,@LicenseeID -- Daily Racing Win Loss
					FROM bodb_licensee.dbo.LicenseeUserFunctions WITH (NOLOCK)
					WHERE LicenseeID=@LicenseeID AND FunctionID =27 --- Licensee WinLoss Report 
					UNION
					SELECT UserID,22 ,@LicenseeID -- Racing
					FROM bodb_licensee.dbo.LicenseeUserFunctions WITH (NOLOCK)
					WHERE LicenseeID=@LicenseeID AND FunctionID =27 --- Licensee WinLoss Report 
				
			END 
		IF @ProductID IN (4,5)
			BEGIN 
				INSERT INTO bodb_licensee.dbo.LicenseeFunctions(LicenseeID,FunctionID)
				SELECT @LicenseeID,27 -- Licensee WinLoss Report
				
				INSERT INTO bodb_licensee.dbo.LicenseeUserFunctions(UserID,FunctionID,LicenseeId)
				SELECT UserID,27,@LicenseeID -- Licensee Winloss Report
				FROM bodb_licensee.dbo.LicenseeUser WITH (NOLOCK)
				WHERE LicenseeID=@LicenseeID
				AND isActive=1
				
			END
		IF @ProductID =3 --- BA 	
			BEGIN 
				DECLARE @tblCust AS TABLE (ID INT IDENTITY(1,1), CustID INT )
				DECLARE @CustID INT 
				DECLARE @MaxID  INT
				DECLARE @i 		INT					
				
				INSERT INTO bodb_licensee.dbo.LicenseeUserFunctions(UserID,FunctionID,LicenseeId)
				SELECT UserID,27,@LicenseeID -- Licensee Winloss Report
				FROM bodb_licensee.dbo.LicenseeUser WITH (NOLOCK)
				WHERE LicenseeID=@LicenseeID
				AND isActive=1
					
				INSERT INTO @tblCust
				SELECT UserID
				FROM bodb_licensee.dbo.LicenseeUser WITH (NOLOCK)
					WHERE LicenseeID=@LicenseeID 
					AND isActive=1
				SELECT @MaxID=MAX(ID) FROM @tblCust
				SET @i=1
				WHILE (@i<=@MaxID)
				BEGIN 
					SELECT @CustID=CustID FROM @tblCust WHERE ID=@i
					
					EXEC DBTRANS.bodb02.dbo.Lrf_CustomerUpdMemberBAStatus
					@LicenseeID  =@LicenseeID,
					@CustID 	 =@CustID,
					@ModifyBy    =@usrID,
					@IsBA        = 1,
					@IsAdmin     = 0,
					@Language    = 'en-us',
					@IP          = @IP,
					@ErrCode     = @ErrCode  ,
					@ErrMsg      = @ErrMsg
					SET @i=@i+1
					
					IF @ErrCode <> 0
						RETURN
				END	
			END 
		
		--- update KPI active
		IF EXISTS (SELECT 1 FROM bodb_licensee.dbo.SystemLicensee WITH (NOLOCK) WHERE systemID=5 AND LicenseeID=@LicenseeID)
			BEGIN 
				UPDATE bodb_licensee.dbo.SystemLicensee 
				SET isActive=1
				WHERE SystemID=5 AND LicenseeID=@LicenseeID 
			END 
		ELSE 
			BEGIN 
				INSERT INTO bodb_licensee.dbo.SystemLicensee
				SELECT 5,@licenseeID, 1
			END 
		SELECT @ErrMsg='The ProductID ='''+convert(varchar,@ProductID)+'''has been offer for  LicenseeID='''+convert(varchar,@LicenseeID)+''''
						,@ErrCode=0
				Return			
END
----------------------------------------------------write log-------------------------------------------------------------------------------------------
SELECT @LogSPData = '<OA_LicenseeProductAddNew="'+ COALESCE(CAST(@LicenseeID as VARCHAR(50)),SPACE(1)) + '" ' +
					'UserID="'+ COALESCE(CAST(@usrID as VARCHAR(50)),SPACE(1)) + '" ' +
					'CustID="'+ COALESCE(CAST(NULL as VARCHAR(50)),SPACE(1)) + '" ' +
					'Language="'+ COALESCE(CAST(NULL as VARCHAR(10)),SPACE(1)) + '" ' +
					'IP="'+ COALESCE(CAST(@IP as VARCHAR(40)),SPACE(1)) + '" ' +
					'ErrCode="'+ COALESCE(CAST(@ErrCode as VARCHAR(50)),SPACE(1)) + '" ' +
					'ErrMsg="'+ COALESCE(CAST(@ErrMsg as VARCHAR(5000)),SPACE(1))+ '" />'


SET @endRun = GETDATE()
SET @duration  = datediff (millisecond,@startRun,@endRun)

EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP 
		@UserID = @usrID,
		@TrackingValue = @LogSPData,
		@TrackingValue2 = '',
		@duration = @duration
		
SET NOCOUNT OFF
-------------------------------------------------------------------------------------------------------------------------------------------------------------
GO
GRANT EXECUTE ON [dbo].[OA_LicenseeProductAddNew] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_LicenseeProductAddNew] TO [vnteam]