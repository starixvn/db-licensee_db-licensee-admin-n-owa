 set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go



ALTER  PROCEDURE [dbo].[OA_LicenseeProductDelete]
	@LicenseeID INT,
	@ProductID INT,
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
DECLARE @startRun DATETIME
DECLARE @endRun DATETIME
DECLARE @duration INT
DECLARE @LogSPData VARCHAR(5000)
SET @startRun = GETDATE()


	BEGIN
		IF NOT EXISTS (
				SELECT 1 FROM bodb_licensee.dbo.LicenseeProduct3rd WITH (NOLOCK) 
				WHERE LicenseeID=@LicenseeID
					AND ProductID=@ProductID
				)
			
			BEGIN 
				SELECT @ErrMsg='This product has been disable for LicenseeID='''+convert(varchar,@LicenseeID)+''''
						,@ErrCode=2
				Return
			END
		ELSE 
		BEGIN 
			DELETE FROM bodb_licensee.dbo.LicenseeProduct3rd
			WHERE LicenseeID=@LicenseeID
				AND ProductID=@ProductID
			IF @ProductID IN (2,4,5) -- Number Game, Live Casino, Virtual Sport
				
				BEGIN 
					---totalbet/numberGame
					DELETE FROM bodb_licensee.dbo.LicenseeFunctions
					WHERE  LicenseeID=@LicenseeID
						AND FunctionID=23
					DELETE FROM bodb_licensee.dbo.LicenseeUserFunctions
					WHERE LicenseeID=@LicenseeID
						AND FunctionID=23
				END 
			IF @ProductID=1 --- Horse Racing
				BEGIN 
					DELETE FROM bodb_licensee.dbo.LicenseeFunctions
					WHERE  LicenseeID=@LicenseeID 
						AND FunctionID IN (34,35,22 ) --- Racing Commission, Daily Racing Winloss ,Racing
				END 
			
			IF @ProductID=3	
				BEGIN
					DECLARE @tblCust AS TABLE (ID INT IDENTITY(1,1), CustID INT )
					DECLARE @CustID INT 
					DECLARE @MaxID  INT
					DECLARE @i 		INT	
					
					DELETE FROM bodb_licensee.dbo.LicenseeUserFunctions
						   WHERE LicenseeID=@LicenseeID AND FunctionID=27 -- Licensee Winloss
					INSERT INTO @tblCust
					SELECT CustID
					FROM bodb_licensee.dbo.LicenseeCust WITH (NOLOCK)
						WHERE LicenseeID=@LicenseeID 
					SELECT @MaxID=MAX(ID) FROM @tblCust
					SET @i=1
					WHILE (@i<=@MaxID)
					BEGIN 
						SELECT @CustID=CustID FROM @tblCust WHERE ID=@i
						
						EXEC DBTRANS.bodb02.dbo.Lrf_CustomerUpdMemberBAStatus
						@LicenseeID  =@LicenseeID,
						@CustID 	 =@CustID,
						@ModifyBy    =@usrID,
						@IsBA        = 0,
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
		
			UPDATE bodb_licensee.dbo.SystemLicensee
			SET isActive=0
			WHERE LicenseeID=@LicenseeID
				AND SystemID=5
			
			SELECT @ErrMsg='The ProductID ='''+convert(varchar,@ProductID)+''' has been disable for LicenseeID='''+convert(varchar,@LicenseeID)+'''succesfull'
					,@ErrCode=0
			Return		
		END 
	END
----------------------------------------------------write log-------------------------------------------------------------------------------------------
	SELECT @LogSPData = '<OA_LicenseeProductDelete="'+ COALESCE(CAST(@LicenseeID as VARCHAR(50)),SPACE(1)) + '" ' +
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
-------------------------------------------------------------------------------------------------------------------------------------------------------------
GO
GRANT EXECUTE ON [dbo].[OA_LicenseeProductDelete] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_LicenseeProductDelete] TO [vnteam]